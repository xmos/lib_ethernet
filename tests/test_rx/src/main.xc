// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

port p_smi_mdio   = on tile[0]: XS1_PORT_1M;
port p_smi_mdc    = on tile[0]: XS1_PORT_1N;
port p_eth_rxclk  = on tile[0]: XS1_PORT_1J;
port p_eth_rxd    = on tile[0]: XS1_PORT_4E;
port p_eth_txd    = on tile[0]: XS1_PORT_4F;
port p_eth_rxdv   = on tile[0]: XS1_PORT_1K;
port p_eth_txen   = on tile[0]: XS1_PORT_1L;
port p_eth_txclk  = on tile[0]: XS1_PORT_1I;
port p_eth_int    = on tile[0]: XS1_PORT_1O;
port p_eth_rxerr  = on tile[0]: XS1_PORT_1P;
port p_eth_dummy  = on tile[0]: XS1_PORT_8C;

clock eth_rxclk   = on tile[0]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[0]: XS1_CLKBLK_2;


void test_rx(client ethernet_if eth)
{
  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.vlan = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;
  eth.add_macaddr_filter(macaddr_filter);

  for (int i = 0; i < 3; i++) {
    select {
    case eth.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      eth.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);
      debug_printf("Received packet, type=%d, len=%d.\n",
                   packet_info.type, packet_info.len);
      int step = rxbuf[7] - rxbuf[6];
      debug_printf("Step = %d\n", step);
      for (size_t i = 6; i < packet_info.len - 1; i++) {
        if ((uint8_t) (rxbuf[i+1] - rxbuf[i]) != step) {
          debug_printf("ERROR: byte %d is %d more than byte %d (expected %d)\n",
                       i+1, rxbuf[i+1] - rxbuf[i], i, step);
        }
      }
      break;
    }
  }
  _exit(0);
}

#define ETH_RX_BUFFER_SIZE_WORDS 1600

int main()
{
  ethernet_if i_eth[1];
  par {
    #if RT
    on tile[0]: mii_ethernet_rt(i_eth, 1,
                                p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                p_eth_txclk, p_eth_txen, p_eth_txd,
                                eth_rxclk, eth_txclk,
                                2000, 2000, 2000, 2000, 1);
    #else
    on tile[0]: mii_ethernet(i_eth, 1,
                             p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                             p_eth_txclk, p_eth_txen, p_eth_txd,
                             p_eth_dummy,
                             eth_rxclk, eth_txclk,
                             ETH_RX_BUFFER_SIZE_WORDS);
    #endif

    on tile[0]: test_rx(i_eth[0]);
  }
  return 0;
}
