// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved

#include <xs1.h>
#include <platform.h>
#include <string.h>
#include "ethernet.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#include "ports.h"

port p_ctrl = on tile[0]: XS1_PORT_1A;
#include "control.xc"

#include "helpers.xc"

#if ETHERNET_SUPPORT_HP_QUEUES

typedef interface loopback_if {
  [[notification]] slave void packet_ready();
  [[clears_notification]] void get_packet(unsigned &len, uintptr_t &buf);
} loopback_if;

void test_rx_loopback(streaming chanend c_tx_hp,
                      client loopback_if i_loopback)
{
  set_core_fast_mode_on();

  unsafe {
    while (1) {
      unsigned len;
      uintptr_t buf;

      select {
      case i_loopback.packet_ready():
        i_loopback.get_packet(len, buf);
        break;
      }
      ethernet_send_hp_packet(c_tx_hp, (char *)buf, len, ETHERNET_ALL_INTERFACES);
    }
  }
}

#define NUM_BUF 8

void test_rx(client ethernet_cfg_if cfg,
             streaming chanend c_rx_hp,
             server loopback_if i_loopback,
             client control_if ctrl)
{
  set_core_fast_mode_on();

  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;
  cfg.add_macaddr_filter(0, 1, macaddr_filter);

  // Add the broadcast MAC address
  memset(macaddr_filter.addr, 0xff, 6);
  cfg.add_macaddr_filter(0, 1, macaddr_filter);

  unsigned char rxbuf[NUM_BUF][ETHERNET_MAX_PACKET_SIZE];
  unsigned rxlen[NUM_BUF];
  unsigned wr_index = 0;
  unsigned rd_index = 0;

  int done = 0;
  while (!done) {
    ethernet_packet_info_t packet_info;

    #pragma ordered
    select {
    case ethernet_receive_hp_packet(c_rx_hp, rxbuf[wr_index], packet_info):
      rxlen[wr_index] = packet_info.len;
      wr_index = (wr_index + 1) % NUM_BUF;
      if (wr_index == rd_index) {
        debug_printf("test_rx ran out of buffers\n");
        _exit(1);
      }
      i_loopback.packet_ready();
      break;

    case i_loopback.get_packet(unsigned &len, uintptr_t &buf): {
      len = rxlen[rd_index];
      buf = (uintptr_t)&rxbuf[rd_index];
      rd_index = (rd_index + 1) % NUM_BUF;

      if (rd_index != wr_index)
        i_loopback.packet_ready();
      break;
    }

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

#else

void test_rx(client ethernet_cfg_if cfg,
             client ethernet_rx_if rx,
             client ethernet_tx_if tx,
             client control_if ctrl)
{
  set_core_fast_mode_on();

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

#endif

#define NUM_CFG_IF 1
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  control_if i_ctrl[NUM_CFG_IF];

#if ETHERNET_SUPPORT_HP_QUEUES
  loopback_if i_loopback;
  streaming chan c_rx_hp;
  streaming chan c_tx_hp;
#else
  #define c_rx_hp null
  #define c_tx_hp null
#endif

#if RGMII
  streaming chan c_rgmii_cfg;
#endif

  par {
    #if RGMII

    on tile[1]: rgmii_ethernet_mac(i_rx_lp, NUM_RX_LP_IF,
                                   i_tx_lp, NUM_TX_LP_IF,
                                   c_rx_hp, c_tx_hp,
                                   c_rgmii_cfg,
                                   rgmii_ports,
                                   ETHERNET_DISABLE_SHAPER);
    on tile[1]: rgmii_ethernet_mac_config(i_cfg, NUM_CFG_IF, c_rgmii_cfg);

    #if ETHERNET_SUPPORT_HP_QUEUES
    on tile[0]: test_rx(i_cfg[0], c_rx_hp, i_loopback, i_ctrl[0]);
    on tile[0]: test_rx_loopback(c_tx_hp, i_loopback);
    #else
    on tile[0]: test_rx(i_cfg[0], i_rx_lp[0], i_tx_lp[0], i_ctrl[0]);
    #endif

    #else // RGMII

    #if RT

    on tile[0]: mii_ethernet_rt_mac(i_cfg, NUM_CFG_IF,
                                    i_rx_lp, NUM_RX_LP_IF,
                                    i_tx_lp, NUM_TX_LP_IF,
                                    c_rx_hp, c_tx_hp,
                                    p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                    p_eth_txclk, p_eth_txen, p_eth_txd,
                                    eth_rxclk, eth_txclk,
                                    4000, 4000, ETHERNET_DISABLE_SHAPER);

    on tile[0]: filler(0x1111);
    #if ETHERNET_SUPPORT_HP_QUEUES
    on tile[0]: test_rx(i_cfg[0], c_rx_hp, i_loopback, i_ctrl[0]);
    on tile[0]: test_rx_loopback(c_tx_hp, i_loopback);
    #else
    on tile[0]: test_rx(i_cfg[0], i_rx_lp[0], i_tx_lp[0], i_ctrl[0]);
    #endif

    #else // RT

    // Having 2300 words gives enough for 3 full-sized frames in each bank of the
    // lite buffers. (4500 bytes * 2) / 4 => 2250 words.
    on tile[0]: mii_ethernet_mac(i_cfg, NUM_CFG_IF,
                                 i_rx_lp, NUM_RX_LP_IF,
                                 i_tx_lp, NUM_TX_LP_IF,
                                 p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                 p_eth_txclk, p_eth_txen, p_eth_txd,
                                 p_eth_dummy,
                                 eth_rxclk, eth_txclk,
                                 2300);
    on tile[0]: filler(0x1111);
    on tile[0]: filler(0x2222);
    on tile[0]: filler(0x3333);
    on tile[0]: filler(0x4444);
    on tile[0]: test_rx(i_cfg[0], i_rx_lp[0], i_tx_lp[0], i_ctrl[0]);

    #endif // RT
    #endif // RGMII

    on tile[0]: control(p_ctrl, i_ctrl, NUM_CFG_IF, NUM_CFG_IF);
  }
  return 0;
}
