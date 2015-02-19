// Copyright (c) 2015, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#include "ports.h"

port p_ctrl = on tile[0]: XS1_PORT_1C;
#include "control.xc"

port p_rx_lp_control = on tile[0]: XS1_PORT_1D;

#include "helpers.xc"

void test_rx_hp(client ethernet_cfg_if cfg,
                streaming chanend c_rx_hp,
                client control_if ctrl,
                chanend c_shutdown)
{
  set_core_fast_mode_on();

  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;
  cfg.add_macaddr_filter(0, 1, macaddr_filter);

  unsigned num_rx_bytes = 0;
  int done = 0;
  char seq_id = 0;
  unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
  while (!done) {
    ethernet_packet_info_t packet_info;

    #pragma ordered
    select {
    case ethernet_receive_hp_packet(c_rx_hp, rxbuf, packet_info):
      // Check the first byte after the header (which can be VLAN tagged)
      if (rxbuf[18] != seq_id)
        debug_printf("Packet %d instead of %d\n", rxbuf[18], seq_id);
      seq_id++;
      num_rx_bytes += packet_info.len;
      break;

    case ctrl.status_changed():
      status_t status;
      ctrl.get_status(status);
      if (status == STATUS_DONE)
        done = 1;
      break;
    }
  }
  debug_printf("Received %d hp bytes\n", num_rx_bytes);

  // Indicate that this core has printed its message
  c_shutdown <: done;
  ctrl.set_done();
}

void test_rx_lp(client ethernet_cfg_if cfg,
                client ethernet_rx_if rx,
                client control_if ctrl,
                chanend c_shutdown)
{
  set_core_fast_mode_on();

  ethernet_macaddr_filter_t macaddr_filter;

  size_t index = rx.get_index();

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i + 1;
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  unsigned num_rx_bytes = 0;
  int done = 0;
  while (!done) {

    select {
      // Allow the testbench to control when packets are consumed
    case p_rx_lp_control when pinseq(1) :> int tmp:
      break;
        
    case ctrl.status_changed():
      status_t status;
      ctrl.get_status(status);
      if (status == STATUS_DONE)
        done = 1;
      break;
    }

    if (done)
      break;
    
    #pragma ordered
    select {
    case rx.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);

      if (packet_info.type != ETH_DATA) {
        continue;
      }

      num_rx_bytes += packet_info.len;
      break;

    case ctrl.status_changed():
      status_t status;
      ctrl.get_status(status);
      if (status == STATUS_DONE)
        done = 1;
      break;
    }
  }

  // Wait until the high priority core has finished
  c_shutdown :> done;
  
  debug_printf("Received %d lp bytes\n", num_rx_bytes);
  ctrl.set_done();
}

#define NUM_CFG_IF 2
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  streaming chan c_rx_hp;
  control_if i_ctrl[NUM_CFG_IF];
  chan c_shutdown;

#if RGMII
  streaming chan c_rgmii_cfg;
#endif

  par {
    #if RGMII

    on tile[1]: rgmii_ethernet_mac(i_rx_lp, NUM_RX_LP_IF,
                                   i_tx_lp, NUM_TX_LP_IF,
                                   c_rx_hp, null,
                                   c_rgmii_cfg,
                                   p_eth_rxclk, p_eth_rxer, p_eth_rxd_1000, p_eth_rxd_10_100,
                                   p_eth_rxd_interframe, p_eth_rxdv, p_eth_rxdv_interframe,
                                   p_eth_txclk_in, p_eth_txclk_out, p_eth_txer, p_eth_txen,
                                   p_eth_txd, eth_rxclk, eth_rxclk_interframe, eth_txclk,
                                   eth_txclk_out, ETHERNET_DISABLE_SHAPER);
    on tile[1]: rgmii_ethernet_mac_config(i_cfg, NUM_CFG_IF, c_rgmii_cfg);

    #else // !RGMII

    on tile[0]: mii_ethernet_rt_mac(i_cfg, NUM_CFG_IF,
                                    i_rx_lp, NUM_RX_LP_IF,
                                    i_tx_lp, NUM_TX_LP_IF,
                                    c_rx_hp, null,
                                    p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                    p_eth_txclk, p_eth_txen, p_eth_txd,
                                    eth_rxclk, eth_txclk,
                                    4000, 4000, ETHERNET_DISABLE_SHAPER);
    on tile[0]: filler(0x1111);

    #endif // RGMII

    on tile[0]: test_rx_hp(i_cfg[0], c_rx_hp, i_ctrl[0], c_shutdown);
    on tile[0]: test_rx_lp(i_cfg[1], i_rx_lp[0], i_ctrl[1], c_shutdown);

    on tile[0]: control(p_ctrl, i_ctrl, NUM_CFG_IF, NUM_CFG_IF);
  }
  return 0;
}
