// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>
#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "xta_test_pragmas.h"
#include "helpers.xc"

#include "ports.h"
port p_test_ctrl = on tile[0]: XS1_PORT_1C;

struct test_packet { int len; int step; int tagged; }
test_packets[] =
  {
    { 60, 1, 0 },
    { ETHERNET_MAX_PACKET_SIZE, 5, 0 },
    { 60, 1, 1 },
    { ETHERNET_MAX_PACKET_SIZE, 5, 1 },
  };

void test_tx(client ethernet_tx_if tx, streaming chanend ? c_tx_hp)
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

    if (isnull(c_tx_hp)) {
      tx.send_packet(data, test_packets[i].len, ETHERNET_ALL_INTERFACES);
    }
    else {
      c_tx_hp <: test_packets[i].len;
      sout_char_array(c_tx_hp, data, test_packets[i].len);
    }
  }

  // Give time for the packet to start to be sent in the case of the RT MAC
  timer t;
  int time;
  t :> time;
  t when timerafter(time + 5000) :> time;

  // Signal that all packets have been sent
  p_test_ctrl <: 1;
}

#define ETH_RX_BUFFER_SIZE_WORDS 1600

#define NUM_CFG_IF 1
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  streaming chan c_rx_hp;
  streaming chan c_tx_hp;

  par {
    #if RGMII

    on tile[1]: rgmii_ethernet_mac(i_cfg, NUM_CFG_IF,
                                   i_rx_lp, NUM_RX_LP_IF,
                                   i_tx_lp, NUM_TX_LP_IF,
                                   c_rx_hp, c_tx_hp,
                                   p_eth_rxclk, p_eth_rxer, p_eth_rxd_1000, p_eth_rxd_10_100,
                                   p_eth_rxd_interframe, p_eth_rxdv, p_eth_rxdv_interframe,
                                   p_eth_txclk_in, p_eth_txclk_out, p_eth_txer, p_eth_txen,
                                   p_eth_txd, eth_rxclk, eth_rxclk_interframe, eth_txclk,
                                   eth_txclk_out);

    on tile[0]: {
      // Give time for the packet to start to be sent in the case of the RT MAC
      timer t;
      int time;
      t :> time;
      t when timerafter(time + 5000) :> time;

      test_tx(i_tx_lp[0], c_tx_hp);
    }

    #else // RGMII

    #if RT
    on tile[0]: mii_ethernet_rt(i_cfg, NUM_CFG_IF,
                                i_rx_lp, NUM_RX_LP_IF,
                                i_tx_lp, NUM_TX_LP_IF,
                                c_rx_hp, c_tx_hp,
                                p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                p_eth_txclk, p_eth_txen, p_eth_txd,
                                eth_rxclk, eth_txclk,
                                2000, 2000, 2000, 2000, 1);
    on tile[0]: filler(0x1111);
    on tile[0]: filler(0x2222);
    on tile[0]: filler(0x3333);

    #if ETHERNET_SUPPORT_HP_QUEUES
    on tile[0]: test_tx(i_tx_lp[0], c_tx_hp);
    #else
    on tile[0]: test_tx(i_tx_lp[0], null);
    #endif

    #else // RT
    on tile[0]: mii_ethernet(i_cfg, NUM_CFG_IF,
                             i_rx_lp, NUM_RX_LP_IF,
                             i_tx_lp, NUM_TX_LP_IF,
                             p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                             p_eth_txclk, p_eth_txen, p_eth_txd,
                             p_eth_dummy,
                             eth_rxclk, eth_txclk,
                             ETH_RX_BUFFER_SIZE_WORDS);
    on tile[0]: filler(0x1111);
    on tile[0]: filler(0x2222);
    on tile[0]: filler(0x3333);
    on tile[0]: filler(0x4444);
    on tile[0]: filler(0x5555);

    on tile[0]: test_tx(i_tx_lp[0], null);

    #endif // RT
    #endif // RGMII

  }
  return 0;
}