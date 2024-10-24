// Copyright 2014-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include <debug_print.h>
#include "otp_board_info.h"
#include "ethernet.h"
#include "icmp.h"
#include "smi.h"



port p_eth_txd    = on tile[1]: XS1_PORT_4A;
port p_eth_rxdv   = on tile[1]: XS1_PORT_1A;
port p_eth_txen   = on tile[1]: XS1_PORT_1B;
port p_eth_txclk  = on tile[1]: XS1_PORT_1O;
port p_eth_rxerr  = on tile[1]: XS1_PORT_1C;
port p_eth_rxclk  = on tile[1]: XS1_PORT_1M;
port p_eth_rxd    = on tile[1]: XS1_PORT_4B;
port p_eth_dummy  = on tile[1]: XS1_PORT_8C;

clock eth_rxclk   = on tile[1]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[1]: XS1_CLKBLK_2;

port p_smi_mdio   = on tile[0]: XS1_PORT_1O;
port p_smi_mdc    = on tile[0]: XS1_PORT_1N;
port port_led     = on tile[0]: XS1_PORT_4C; // Also RST_N

port p_clkin      = on tile[1]: XS1_PORT_1D;
clock clk_clkin   = on tile[1]: XS1_CLKBLK_3;


// These ports are for accessing the OTP memory
otp_ports_t otp_ports = on tile[0]: OTP_PORTS_INITIALIZER;

static unsigned char ip_address[4] = {192, 169, 1, 178};

// An enum to manage the array of connections from the ethernet component
// to its clients.
enum eth_clients {
  ETH_TO_ICMP,
  NUM_ETH_CLIENTS
};

enum cfg_clients {
  CFG_TO_ICMP,
  CFG_TO_PHY_DRIVER,
  NUM_CFG_CLIENTS
};

[[combinable]]
void lan8710a_phy_driver(client interface smi_if smi,
                         client interface ethernet_cfg_if eth) {
  port_led <: 0;
  delay_milliseconds(200);
  port_led <: 0x1;
  

  ethernet_link_state_t link_state = ETHERNET_LINK_DOWN;
  ethernet_speed_t link_speed = LINK_100_MBPS_FULL_DUPLEX;
  const int link_poll_period_ms = 1000;
  const int phy_address = 0x0;
  timer tmr;
  int t;
  tmr :> t;

  while (smi_phy_is_powered_down(smi, phy_address));

  smi_configure(smi, phy_address, LINK_100_MBPS_FULL_DUPLEX, SMI_ENABLE_AUTONEG);

  while (1) {
    select {
    case tmr when timerafter(t) :> t:
      ethernet_link_state_t new_state = smi_get_link_state(smi, phy_address);
      // Read LAN8710A status register bit 2 to get the current link speed
      if ((new_state == ETHERNET_LINK_UP) &&
         ((smi.read_reg(phy_address, 0x1F) >> 2) & 1)) {
        link_speed = LINK_10_MBPS_FULL_DUPLEX;
      }
      else {
        link_speed = LINK_100_MBPS_FULL_DUPLEX;
      }
      if (new_state != link_state) {
        link_state = new_state;
        eth.set_link_state(0, new_state, link_speed);
      }
      t += link_poll_period_ms * XS1_TIMER_KHZ;
      debug_printf("State: %u speed: %s\n", link_state, link_speed == LINK_100_MBPS_FULL_DUPLEX ? "100" : "10");
      break;
    }
  }
}

void init_eth_clock(void){
    configure_clock_ref(clk_clkin, (4 / 2)); // 100 / 4 = 25 MHz
    set_port_clock(p_clkin, clk_clkin);
    set_port_mode_clock(p_clkin);
    start_clock(clk_clkin);
}


#define ETH_RX_BUFFER_SIZE_WORDS 1600

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_rx_if i_rx[NUM_ETH_CLIENTS];
  ethernet_tx_if i_tx[NUM_ETH_CLIENTS];
  smi_if i_smi;

  par {
    on tile[1]: {
                    init_eth_clock();
                    mii_ethernet_mac(i_cfg, NUM_CFG_CLIENTS,
                                     i_rx, NUM_ETH_CLIENTS,
                                     i_tx, NUM_ETH_CLIENTS,
                                     p_eth_rxclk, p_eth_rxerr,
                                     p_eth_rxd, p_eth_rxdv,
                                     p_eth_txclk, p_eth_txen, p_eth_txd,
                                     p_eth_dummy,
                                     eth_rxclk, eth_txclk,
                                     ETH_RX_BUFFER_SIZE_WORDS);
                }

    on tile[0]: lan8710a_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER]);

    on tile[0]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    on tile[0]: icmp_server(i_cfg[CFG_TO_ICMP],
                            i_rx[ETH_TO_ICMP], i_tx[ETH_TO_ICMP],
                            ip_address, otp_ports);
  }
  return 0;
}
