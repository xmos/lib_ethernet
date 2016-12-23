// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#include "ports.h"

port p_ctrl = on tile[0]: XS1_PORT_1C;
#include "control.xc"

#define NUM_CFG_IF 3
#define NUM_RX_LP_IF 2
#define NUM_TX_LP_IF 1
#define NUM_LP_CLIENTS 2

port p_rx_lp_control[NUM_LP_CLIENTS] = on tile[0]: { XS1_PORT_1D, XS1_PORT_1E };

#include "helpers.xc"

void test_rx_hp(client ethernet_cfg_if cfg,
                streaming chanend c_rx_hp,
                client control_if ctrl,
                chanend c_shutdown[n],
                size_t n)
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
  for (size_t i = 0; i < n; ++i) {
    c_shutdown[i] <: done;
    c_shutdown[i] :> done;
  }
  ctrl.set_done();
}

void test_rx_lp(client ethernet_cfg_if cfg,
                client ethernet_rx_if rx,
                client control_if ctrl,
                chanend c_shutdown,
                size_t client_num,
                port p_rx_lp_control)
{
  set_core_fast_mode_on();

  ethernet_macaddr_filter_t macaddr_filter;

  size_t index = rx.get_index();

  // Add the unicast address
  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++) {
    macaddr_filter.addr[i] = i + client_num;
  }
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  // Add the broadcast address
  for (int i = 0; i < 6; i++) {
    macaddr_filter.addr[i] = 0xff;
  }
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
  debug_printf("LP client %d received %d bytes\n", client_num, num_rx_bytes);
  c_shutdown <: done;
  ctrl.set_done();
}

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  streaming chan c_rx_hp;
  control_if i_ctrl[NUM_CFG_IF];
  chan c_shutdown[NUM_LP_CLIENTS];

#if RGMII
  streaming chan c_rgmii_cfg;
#endif

  par {
    #if RGMII

    on tile[1]: rgmii_ethernet_mac(i_rx_lp, NUM_RX_LP_IF,
                                   i_tx_lp, NUM_TX_LP_IF,
                                   c_rx_hp, null,
                                   c_rgmii_cfg,
                                   rgmii_ports,
                                   ETHERNET_DISABLE_SHAPER);
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

    #endif // RGMII

    on tile[0]: test_rx_hp(i_cfg[0], c_rx_hp, i_ctrl[0], c_shutdown, NUM_LP_CLIENTS);
    on tile[0]: test_rx_lp(i_cfg[1], i_rx_lp[0], i_ctrl[1], c_shutdown[0], 1,
      p_rx_lp_control[0]);
    on tile[0]: test_rx_lp(i_cfg[2], i_rx_lp[1], i_ctrl[2], c_shutdown[1], 2,
      p_rx_lp_control[1]);

    on tile[0]: control(p_ctrl, i_ctrl, NUM_CFG_IF, NUM_CFG_IF);
  }
  return 0;
}
