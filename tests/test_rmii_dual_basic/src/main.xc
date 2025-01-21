// Copyright 2024-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <platform.h>
#include <string.h>
#include "ethernet.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#include "ports_rmii.h"

#if ETHERNET_SUPPORT_HP_QUEUES
typedef interface loopback_if {
  [[notification]] slave void packet_ready();
  [[clears_notification]] void get_packet(unsigned &len, uintptr_t &buf);
} loopback_if;

void test_loopback(streaming chanend c_tx_hp,
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
      ethernet_send_hp_packet(c_tx_hp, (char *)buf, len, 1);
    }
  }
}

#define NUM_BUF 8

void test_rx(client ethernet_cfg_if cfg,
             streaming chanend c_rx_hp,
             server loopback_if i_loopback)
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

  cfg.forward_packets_as_hp(1); // put the forwarding packets in hp queue. For testing only. In reality, client doesn't get to tell this to the Mac.

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
    }
  }
}

#else
void test_rx_loopback(client ethernet_cfg_if cfg,
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
      tx.send_packet(rxbuf, packet_info.len, 1);
      break;
    }
  }
}
#endif


#define NUM_CFG_IF 1
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

port p_rx_lp_control_1 = on tile[0]:XS1_PORT_1G;
port p_rx_lp_control_2 = on tile[0]:XS1_PORT_1N;

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];

#if ETHERNET_SUPPORT_HP_QUEUES
  loopback_if i_loopback;
  streaming chan c_rx_hp;
  streaming chan c_tx_hp;
#else
  #define c_rx_hp null
  #define c_tx_hp null
#endif



  par {

      unsafe{rmii_ethernet_rt_mac_dual(i_cfg, NUM_CFG_IF,
                                      i_rx_lp, NUM_RX_LP_IF,
                                      i_tx_lp, NUM_TX_LP_IF,
                                      c_rx_hp, c_tx_hp,
                                      p_eth_clk,
                                      &p_eth_rxd, p_eth_rxdv,
                                      p_eth_txen, &p_eth_txd,
                                      eth_rxclk, eth_txclk,
                                      &p_eth_rxd_2, p_eth_rxdv_2,
                                      p_eth_txen_2, &p_eth_txd_2,
                                      eth_rxclk_2, eth_txclk_2,
                                      4000, 4000, ETHERNET_ENABLE_SHAPER);}

#if ETHERNET_SUPPORT_HP_QUEUES
    test_rx(i_cfg[0], c_rx_hp, i_loopback);
    test_loopback(c_tx_hp, i_loopback);
#else
    test_rx_loopback(i_cfg[0], i_rx_lp[0], i_tx_lp[0]);
#endif

  }
  return 0;
}

