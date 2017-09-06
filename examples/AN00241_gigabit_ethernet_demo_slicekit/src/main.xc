// Copyright (c) 2015-2017, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include "otp_board_info.h"
#include "ethernet.h"
#include "icmp.h"
#include "smi.h"
#include "debug_print.h"

// These ports are for accessing the OTP memory
otp_ports_t otp_ports = on tile[0]: OTP_PORTS_INITIALIZER;

// Tile number used in app note text
rgmii_ports_t rgmii_ports = on tile[1]: RGMII_PORTS_INITIALIZER;

port p_smi_mdio   = PORT_SMI_MDIO;
port p_smi_mdc    = PORT_SMI_MDC;
port p_eth_reset  = PORT_ETH_RST;

static unsigned char ip_address[4] = {192, 168, 1, 178};


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

#define KSZ9031RNX_MMD_PAD_SKEW_DEV_ADDR 2
#define KSZ9031RNX_MMD_PAD_SKEW_CONTROL_PADS 4
#define KSZ9031RNX_MMD_PAD_SKEW_RX_DATA_PADS 5
#define KSZ9031RNX_MMD_PAD_SKEW_TX_DATA_PADS 6
#define KSZ9031RNX_MMD_PAD_SKEW_CLOCK_PADS 8

#define PAD_SKEW_RXDV 7
#define PAD_SKEW_RXD 7
#define PAD_SKEW_RXC 15
#define PAD_SKEW_TXEN 7
#define PAD_SKEW_TXD 7
#define PAD_SKEW_TXC 15

static void configure_phy_delays(client interface smi_if smi, int phy_address)
{
  smi_mmd_write(smi, phy_address, KSZ9031RNX_MMD_PAD_SKEW_DEV_ADDR,
                KSZ9031RNX_MMD_PAD_SKEW_CONTROL_PADS,
                (PAD_SKEW_RXDV << 4) | PAD_SKEW_TXEN);

  smi_mmd_write(smi, phy_address, KSZ9031RNX_MMD_PAD_SKEW_DEV_ADDR,
                KSZ9031RNX_MMD_PAD_SKEW_RX_DATA_PADS,
                (PAD_SKEW_RXD << 12) | (PAD_SKEW_RXD << 8) | (PAD_SKEW_RXD << 4) | PAD_SKEW_RXD);

  smi_mmd_write(smi, phy_address, KSZ9031RNX_MMD_PAD_SKEW_DEV_ADDR,
                KSZ9031RNX_MMD_PAD_SKEW_TX_DATA_PADS,
                (PAD_SKEW_TXD << 12) | (PAD_SKEW_TXD << 8) | (PAD_SKEW_TXD << 4) | PAD_SKEW_TXD);

  smi_mmd_write(smi, phy_address, KSZ9031RNX_MMD_PAD_SKEW_DEV_ADDR,
                KSZ9031RNX_MMD_PAD_SKEW_CLOCK_PADS,
                (PAD_SKEW_TXC << 5) | (PAD_SKEW_RXC));
}

[[combinable]]
void ksz9031_phy_driver(client interface smi_if smi,
                        client interface ethernet_cfg_if eth) {
  ethernet_link_state_t link_state = ETHERNET_LINK_DOWN;
  ethernet_speed_t link_speed = LINK_1000_MBPS_FULL_DUPLEX;
  const int phy_reset_delay_ms = 10;
  const int link_poll_period_ms = 1000;
  const int phy_address = 3;
  timer tmr;
  int t;
  tmr :> t;
  p_eth_reset <: 0;
  delay_milliseconds(phy_reset_delay_ms);
  p_eth_reset <: 1;
  delay_microseconds(100);

  while (smi_phy_is_powered_down(smi, phy_address));

  smi_phy_reset(smi, phy_address); // optional?

  configure_phy_delays(smi, phy_address);

  smi_configure(smi, phy_address, LINK_1000_MBPS_FULL_DUPLEX, SMI_ENABLE_AUTONEG);

  while (1) {
    select {
    case tmr when timerafter(t) :> t:
      ethernet_link_state_t new_state = smi_get_link_state(smi, phy_address);
      // Poll status register bits 15:14 to get the current link speed
      if (new_state == ETHERNET_LINK_UP) {
        link_speed = (ethernet_speed_t)(smi.read_reg(phy_address, 0x11) >> 14) & 3;
      }
      if (new_state != link_state) {
        link_state = new_state;
        eth.set_link_state(0, new_state, link_speed);
        debug_printf("Link state %d\n", new_state);
      }
      t += link_poll_period_ms * XS1_TIMER_KHZ;
      break;
    }
  }
}

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_rx_if i_rx[NUM_ETH_CLIENTS];
  ethernet_tx_if i_tx[NUM_ETH_CLIENTS];
  streaming chan c_rgmii_cfg;
  smi_if i_smi;

  par {
    on tile[1]: rgmii_ethernet_mac(i_rx, NUM_ETH_CLIENTS,
                                   i_tx, NUM_ETH_CLIENTS,
                                   null, null,
                                   c_rgmii_cfg,
                                   rgmii_ports, 
                                   ETHERNET_DISABLE_SHAPER);
    on tile[1].core[0]: rgmii_ethernet_mac_config(i_cfg, NUM_CFG_CLIENTS, c_rgmii_cfg);
    on tile[1].core[0]: ksz9031_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER]);
  
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    on tile[0]: icmp_server(i_cfg[CFG_TO_ICMP],
                            i_rx[ETH_TO_ICMP], i_tx[ETH_TO_ICMP],
                            ip_address, otp_ports);
  }
  return 0;
}
