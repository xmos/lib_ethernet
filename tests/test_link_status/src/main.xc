// Copyright (c) 2014-2017, XMOS Ltd, All rights reserved

#include <xs1.h>
#include <platform.h>
#include <string.h>
#include "ethernet.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#include "ports.h"

#define MS_TICKS 100000

port p_ctrl = on tile[0]: XS1_PORT_1A;
#include "control.xc"

#include "helpers.xc"

#if RGMII
#define SPEED LINK_1000_MBPS_FULL_DUPLEX
#else
#define SPEED LINK_100_MBPS_FULL_DUPLEX
#endif

void link_status_control(client ethernet_cfg_if cfg, chanend c)
{
  size_t ifnum;
  c :> ifnum;
  cfg.set_link_state(ifnum, ETHERNET_LINK_UP, SPEED);
  c :> ifnum;
  cfg.set_link_state(ifnum, ETHERNET_LINK_DOWN, SPEED);
  c :> ifnum;
  cfg.set_link_state(ifnum, ETHERNET_LINK_UP, SPEED);
  c :> ifnum;
  cfg.set_link_state(ifnum, ETHERNET_LINK_DOWN, SPEED);
}

void test_link_status(client ethernet_cfg_if cfg,
             client ethernet_rx_if rx,
             client ethernet_tx_if tx,
             client control_if ctrl,
             chanend c)
{
  set_core_fast_mode_on();

  size_t index = rx.get_index();

  cfg.enable_link_status_notification(index);

  int events_expected = 4;
  while (events_expected) {
    c <: index;

    select {
    case rx.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);
      if (packet_info.type == ETH_IF_STATUS) {
        debug_printf("Link status %s\n", rxbuf[0] == ETHERNET_LINK_DOWN ? "DOWN" : "UP");
      } else {
        debug_printf("Unwanted packet\n");
      }
      break;
    }

    events_expected -= 1;
  }
  ctrl.set_done();
}

#define NUM_CFG_IF 2
#define NUM_CTRL_IF 1
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  control_if i_ctrl[NUM_CTRL_IF];

  chan c;

#if RGMII
  streaming chan c_rgmii_cfg;
#endif

  par {
    #if RGMII

    on tile[1]: rgmii_ethernet_mac(i_rx_lp, NUM_RX_LP_IF,
                                   i_tx_lp, NUM_TX_LP_IF,
                                   null, null,
                                   c_rgmii_cfg,
                                   rgmii_ports,
                                   ETHERNET_DISABLE_SHAPER);
    on tile[1]: rgmii_ethernet_mac_config(i_cfg, NUM_CFG_IF, c_rgmii_cfg);

    on tile[0]: test_link_status(i_cfg[0], i_rx_lp[0], i_tx_lp[0], i_ctrl[0], c);
    on tile[0]: link_status_control(i_cfg[1], c);

    #else // RGMII

    #if RT

    on tile[0]: mii_ethernet_rt_mac(i_cfg, NUM_CFG_IF,
                                    i_rx_lp, NUM_RX_LP_IF,
                                    i_tx_lp, NUM_TX_LP_IF,
                                    null, null,
                                    p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                    p_eth_txclk, p_eth_txen, p_eth_txd,
                                    eth_rxclk, eth_txclk,
                                    4000, 4000, ETHERNET_DISABLE_SHAPER);

    on tile[0]: filler(0x1111);
    on tile[0]: test_link_status(i_cfg[0], i_rx_lp[0], i_tx_lp[0], i_ctrl[0], c);
    on tile[0]: link_status_control(i_cfg[1], c);

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
    on tile[0]: test_link_status(i_cfg[0], i_rx_lp[0], i_tx_lp[0], i_ctrl[0], c);
    on tile[0]: link_status_control(i_cfg[1], c);

    #endif // RT
    #endif // RGMII

    on tile[0]: control(p_ctrl, i_ctrl, NUM_CTRL_IF, NUM_CTRL_IF);
  }
  return 0;
}
