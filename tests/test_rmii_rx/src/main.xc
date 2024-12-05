// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <xs1.h>
#include <platform.h>
#include <string.h>
#include "ethernet.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#include "ports_rmii.h"
#include "control.xc"

#include "helpers.xc"

#define NUM_CFG_IF 1
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

#include <stdio.h>

void test_rx(client ethernet_cfg_if cfg,
             client ethernet_rx_if rx,
             client ethernet_tx_if tx,
             client control_if ctrl)
{
  set_core_fast_mode_on();
  timer t;
  int time;

  ethernet_macaddr_filter_t macaddr_filter;

  size_t index = rx.get_index();

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  // Add the broadcast MAC address
  memset(macaddr_filter.addr, 0xff, 6);
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  int done = 0;
  while (!done) {
    #pragma ordered
    select {
    case rx.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);
      tx.send_packet(rxbuf, packet_info.len, ETHERNET_ALL_INTERFACES);
      break;

    case ctrl.status_changed():
      status_t status;
      ctrl.get_status(status);
      if (status == STATUS_DONE)
        done = 1;
      break;
    }
  }
  ctrl.set_done();
}

int main()
{
    ethernet_cfg_if i_cfg[NUM_CFG_IF];
    ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
    ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
    control_if i_ctrl[NUM_CFG_IF];

#if ETHERNET_SUPPORT_HP_QUEUES
    streaming chan c_rx_hp;
    streaming chan c_tx_hp;
#else
    #define c_rx_hp null
    #define c_tx_hp null
#endif


    par {
        unsafe{rmii_ethernet_rt_mac(i_cfg, NUM_CFG_IF,
                                    i_rx_lp, NUM_RX_LP_IF,
                                    i_tx_lp, NUM_TX_LP_IF,
                                    c_rx_hp, c_tx_hp,
                                    p_eth_clk,
                                    &p_eth_rxd, p_eth_rxdv,
                                    p_eth_txen, &p_eth_txd,
                                    eth_rxclk, eth_txclk,
                                    4000, 4000, ETHERNET_DISABLE_SHAPER);}

        test_rx(i_cfg[0], i_rx_lp[0], i_tx_lp[0], i_ctrl[0]);

        control(p_test_ctrl, i_ctrl, NUM_CFG_IF, NUM_CFG_IF);
    }

    return 0;
}
