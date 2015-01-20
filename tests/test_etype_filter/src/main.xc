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
#include "xta_test_pragmas.h"
#include "helpers.xc"

#include "ports.h"

void test_task(client ethernet_cfg_if cfg,
               client ethernet_rx_if rx,
               uint16_t etype)
{
  ethernet_macaddr_filter_t macaddr_filter;
  timer tmr;
  unsigned t;
  tmr :> t;
  macaddr_filter.vlan = 0;
  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;

  size_t index = rx.get_index();
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  cfg.add_ethertype_filter(index, 0, etype);

  while (1) {
    select {
    case rx.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);
      debug_printf("%d: Received packet, type=%d, len=%d, buf[15]=0x%x.\n",
                   index + 1,
                   packet_info.type, packet_info.len,
                   rxbuf[15]);
      break;
    case tmr when timerafter(t + 10000) :> void:
      if (index == 1)
        _exit(0);
      break;
    }
  }
}

#define ETH_RX_BUFFER_SIZE_WORDS 1600

#define NUM_CFG_IF 2
#define NUM_RX_LP_IF 2
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
    on tile[0]: filler(0x66);
    on tile[0]: filler(0x77);

    #else // RT

    on tile[0]: mii_ethernet(i_cfg, NUM_CFG_IF,
                             i_rx_lp, NUM_RX_LP_IF,
                             i_tx_lp, NUM_TX_LP_IF,
                             p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                             p_eth_txclk, p_eth_txen, p_eth_txd,
                             p_eth_dummy,
                             eth_rxclk, eth_txclk,
                             ETH_RX_BUFFER_SIZE_WORDS);
    on tile[0]: filler(0x44);
    on tile[0]: filler(0x55);
    on tile[0]: filler(0x66);
    on tile[0]: filler(0x77);

    #endif // RT
    #endif // RGMII

    on tile[0]: test_task(i_cfg[0], i_rx_lp[0], 0x1111);
    on tile[0]: test_task(i_cfg[1], i_rx_lp[1], 0x2222);
  }
  return 0;
}