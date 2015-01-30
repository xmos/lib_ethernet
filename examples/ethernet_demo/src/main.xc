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

int main()
{
  ethernet_cfg_if i_cfg[NUM_ETH_CLIENTS];
  ethernet_rx_if i_rx[NUM_ETH_CLIENTS];
  ethernet_tx_if i_tx[NUM_ETH_CLIENTS];
  par {
    on tile[1]: mii_ethernet_mac(i_cfg, NUM_ETH_CLIENTS,
                                 i_rx, NUM_ETH_CLIENTS,
                                 i_tx, NUM_ETH_CLIENTS,
                                 p_eth_rxclk, p_eth_rxerr,
                                 p_eth_rxd, p_eth_rxdv,
                                 p_eth_txclk, p_eth_txen, p_eth_txd,
                                 p_eth_dummy,
                                 eth_rxclk, eth_txclk,
                                 ETH_RX_BUFFER_SIZE_WORDS);

    on tile[1]: icmp_server(i_cfg[ETH_TO_ICMP],
                            i_rx[ETH_TO_ICMP], i_tx[ETH_TO_ICMP],
                            ip_address, otp_ports);
  }
  return 0;
}
