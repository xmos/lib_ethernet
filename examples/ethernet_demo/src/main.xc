// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

/*************************************************************************
 *
 * Ethernet ARP/ICMP demo
 * Note: Only supports unfragmented IP packets
 *
 *************************************************************************/
#include <xs1.h>
#include <platform.h>
#include "otp_board_info.h"
#include "ethernet.h"
#include "icmp.h"
#include "smi.h"

// These ports are for accessing the OTP memory
otp_ports_t otp_ports = on tile[1]: OTP_PORTS_INITIALIZER;

// Here are the port definitions required by ethernet. This port assignment
// is for the L16 sliceKIT with the ethernet slice plugged into the
// CIRCLE slot.
port p_smi_mdio   = on tile[1]: XS1_PORT_1M;
port p_smi_mdc    = on tile[1]: XS1_PORT_1N;
port p_eth_rxclk  = on tile[1]: XS1_PORT_1J;
port p_eth_rxd    = on tile[1]: XS1_PORT_4E;
port p_eth_txd    = on tile[1]: XS1_PORT_4F;
port p_eth_rxdv   = on tile[1]: XS1_PORT_1K;
port p_eth_txen   = on tile[1]: XS1_PORT_1L;
port p_eth_txclk  = on tile[1]: XS1_PORT_1I;
port p_eth_int    = on tile[1]: XS1_PORT_1O;
port p_eth_rxerr  = on tile[1]: XS1_PORT_1P;
port p_eth_dummy  = on tile[1]: XS1_PORT_8C;

clock eth_rxclk   = on tile[1]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[1]: XS1_CLKBLK_2;

static unsigned char ip_address[4] = {192, 168, 1, 178};


// An enum to manager the array of connections from the ethernet component
// to its clients.
enum eth_clients {
  ETH_TO_ICMP,
  NUM_ETH_CLIENTS
};

#define ETH_RX_BUFFER_SIZE_WORDS 1600

// On the ethernet slice card the phy address is configure to be 0
#define ETH_SMI_PHY_ADDRESS 0x0

[[combinable]]
void phy_driver(client interface smi_if smi,
                client interface ethernet_config_if eth_config);

int main()
{
  ethernet_if i_eth[NUM_ETH_CLIENTS];
  ethernet_config_if i_eth_config;
  ethernet_filter_callback_if i_eth_filter;
  smi_if i_smi;
  par {
    on tile[1]: smi(i_smi, ETH_SMI_PHY_ADDRESS, p_smi_mdio, p_smi_mdc);

    on tile[1]:
      {
        char mac_address[6];
        otp_board_info_get_mac(otp_ports, 0, mac_address);
        mii_ethernet(i_eth_filter, i_eth_config,
                     i_eth, NUM_ETH_CLIENTS,
                     mac_address,
                     p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                     p_eth_txclk, p_eth_txen, p_eth_txd,
                     p_eth_dummy,
                     eth_rxclk, eth_txclk,
                     ETH_RX_BUFFER_SIZE_WORDS);
      }

      on tile[1]: arp_ip_filter(i_eth_filter);

      on tile[1].core[0]: icmp_server(i_eth[ETH_TO_ICMP], ip_address);
      on tile[1].core[0]: phy_driver(i_smi, i_eth_config);
  }
  return 0;
}

#define ETHERNET_LINK_POLL_PERIOD_MS 1000
[[combinable]]
void phy_driver(client interface smi_if smi,
                client interface ethernet_config_if eth_config) {
  ethernet_link_state_t link_state = ETHERNET_LINK_DOWN;
  timer tmr;
  int t;
  tmr :> t;


  smi_configure(smi, 1, 1);
  while (1) {
    select {
    case tmr when timerafter(t) :> t:
      int link_up = smi_is_link_up(smi);
      ethernet_link_state_t new_state = link_up ? ETHERNET_LINK_UP :
                                                  ETHERNET_LINK_DOWN;
      if (new_state != link_state) {
        link_state = new_state;
        eth_config.set_link_state(0, ETHERNET_LINK_DOWN);
      }
      t += ETHERNET_LINK_POLL_PERIOD_MS * XS1_TIMER_MHZ * 1000;
      break;
    }
  }
}


