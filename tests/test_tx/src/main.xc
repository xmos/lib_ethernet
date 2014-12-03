// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>
#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "xta_test_pragmas.h"

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
port p_test_ctrl  = on tile[0]: XS1_PORT_1A;

clock eth_rxclk   = on tile[0]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[0]: XS1_CLKBLK_2;


struct test_packet { int len; int step; int tagged; }
test_packets[] =
  {
    { 60, 1, 0 },
    { ETHERNET_MAX_PACKET_SIZE, 5, 0 },
    { 60, 1, 1 },
    { ETHERNET_MAX_PACKET_SIZE, 5, 1 },
  };

void test_tx(client ethernet_if eth)
{
  p_test_ctrl <: 0;
  for (int i = 0; i < sizeof(test_packets)/sizeof(test_packets[0]); i++) {
    char data[ETHERNET_MAX_PACKET_SIZE];

    // src/dst MAC addresses
    size_t j = 0;
    for (; j < 12; j++)
      data[j] = j;

    int len = test_packets[i].len - 14;

    if (test_packets[i].tagged) {
      data[j++] = 0x81;
      data[j++] = 0x00;
      data[j++] = 0x00;
      data[j++] = 0x00;

      // There will be 4 less data bytes with the VLAN/Priority tag
      len -= 4;
    }

    data[j++] = len >> 8;
    data[j++] = len & 0xff;

    int x = 0;
    for (; j < test_packets[i].len; j++) {
      x += test_packets[i].step;
      data[j] = x;
    }

    eth.send_packet(data, test_packets[i].len,
                    ETHERNET_ALL_INTERFACES);
  }

  // Give time for the packet to start to be sent in the case of the RT MAC
  timer t;
  int time;
  t :> time;
  t when timerafter(time + 100) :> time;

  // Signal that all packets have been sent
  p_test_ctrl <: 1;
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
    on tile[0]: test_tx(i_eth[0]);
  }
  return 0;
}
