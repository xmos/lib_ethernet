// Copyright 2014-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include "otp_board_info.h"
#include "ethernet.h"
#include "icmp.h"
#include "smi.h"


port p_eth_rxclk  = PORT_ETH_RXCLK;
port p_eth_rxd    = PORT_ETH_RXD;
port p_eth_txd    = PORT_ETH_TXD;
port p_eth_rxdv   = PORT_ETH_RXDV;
port p_eth_txen   = PORT_ETH_TXEN;
port p_eth_txclk  = PORT_ETH_TXCLK;
port p_eth_rxerr  = PORT_ETH_RXER;
port p_eth_dummy  = on tile[1]: XS1_PORT_8C;

clock eth_rxclk   = on tile[1]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[1]: XS1_CLKBLK_2;

port p_smi_mdio   = PORT_SMI_MDIO;
port p_smi_mdc    = PORT_SMI_MDC;


//static unsigned char ip_address[4] = {192, 168, 1, 178};


[[combinable]]
void lan8710a_phy_driver(client interface smi_if smi,
                         client interface ethernet_cfg_if eth) {
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
      break;
    }
  }
}

#define NUM_CFG_CLIENTS 3
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  smi_if i_smi;
  streaming chan c_rx_hp;
  chan c_shutdown[NUM_RX_LP_IF];

  par {
    on tile[1]: mii_ethernet_rt_mac(i_cfg, NUM_CFG_CLIENTS,
                                i_rx_lp, NUM_RX_LP_IF,
                                i_tx_lp, NUM_TX_LP_IF,
                                c_rx_hp, null,
                                p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                p_eth_txclk, p_eth_txen, p_eth_txd,
                                eth_rxclk, eth_txclk,
                                4000, 4000, ETHERNET_DISABLE_SHAPER);

    on tile[1]: lan8710a_phy_driver(i_smi, i_cfg[0]);

    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    // RX threads
    on tile[0]: test_rx_lp(i_cfg[1],
                            i_rx_lp[0], i_tx_lp[0], c_shutdown[0]);

    on tile[0]: test_rx_hp(i_cfg[2], c_rx_hp, c_shutdown, NUM_RX_LP_IF);

  }
  return 0;
}
