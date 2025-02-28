// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <platform.h>
#include <string.h>
#include "ethernet.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#include "ports_rmii.h"



void loopback(client ethernet_cfg_if cfg,
             client ethernet_rx_if rx,
             client ethernet_tx_if tx)
{
  set_core_fast_mode_on();

  ethernet_macaddr_filter_t macaddr_filter;

  size_t index = rx.get_index();

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++){
    macaddr_filter.addr[i] = i;
  }
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  // Add the broadcast MAC address
  memset(macaddr_filter.addr, 0xff, 6);
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  int done = 0;
  while (!done) {
    select {
    case rx.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);
      tx.send_packet(rxbuf, packet_info.len, ETHERNET_ALL_INTERFACES);
      break;
    }
  }
}


#define NUM_CFG_IF 1
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];


  par {
      // 5 threads total so thread speed = f/5
      rmii_ethernet_rt_mac( i_cfg, NUM_CFG_IF,
                            i_rx_lp, NUM_RX_LP_IF,
                            i_tx_lp, NUM_TX_LP_IF,
                            null, null,
                            p_eth_clk,
                            p_eth_rxd_0,
                            p_eth_rxd_1,
                            RX_PINS,
                            p_eth_rxdv,
                            p_eth_txen,
                            p_eth_txd_0,
                            p_eth_txd_1,
                            TX_PINS,
                            eth_rxclk,
                            eth_txclk,
                            port_timing,
                            4000, 4000,
                            ETHERNET_DISABLE_SHAPER);
      loopback(i_cfg[0], i_rx_lp[0], i_tx_lp[0]);

  }
  return 0;
}

