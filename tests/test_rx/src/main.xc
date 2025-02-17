// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#if RMII
#include "ports_rmii.h"
#else
#include "ports.h"
port p_test_ctrl = on tile[0]: XS1_PORT_1A;
#endif

#include "control.xc"

#include "helpers.xc"

void test_task(client ethernet_cfg_if cfg,
               client ethernet_rx_if rx,
               uint16_t etype,
               int strip,
               client control_if ctrl)
{
  ethernet_macaddr_filter_t macaddr_filter;
  timer tmr;
  unsigned t;
  tmr :> t;
  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;

  size_t index = rx.get_index();
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  cfg.add_ethertype_filter(index, etype);
  if (strip) {
    cfg.enable_strip_vlan_tag(index);
  }

  int done = 0;
  while (!done) {
    select {
    case rx.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);
      debug_printf("%d: Received packet, type=%d, len=%d, buf[12]=0x%x, buf[13]=0x%x, buf[14]=0x%x.\n",
                   index + 1,
                   packet_info.type, packet_info.len,
                   rxbuf[12], rxbuf[13], rxbuf[14]);
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

#define NUM_CFG_IF 4
#define NUM_RX_LP_IF 4
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  control_if i_ctrl[NUM_CFG_IF];

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

    on tile[0]: test_task(i_cfg[2], i_rx_lp[2], 0x3333, 0, i_ctrl[2]);
    on tile[0]: test_task(i_cfg[3], i_rx_lp[3], 0x4444, 0, i_ctrl[3]);

    #else

    #if RT

    #if MII
      on tile[0]: mii_ethernet_rt_mac(i_cfg, NUM_CFG_IF,
                                      i_rx_lp, NUM_RX_LP_IF,
                                      i_tx_lp, NUM_TX_LP_IF,
                                      null, null,
                                      p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                      p_eth_txclk, p_eth_txen, p_eth_txd,
                                      eth_rxclk, eth_txclk,
                                      4000, 4000, ETHERNET_DISABLE_SHAPER);
    #elif RMII
      on tile[0]: rmii_ethernet_rt_mac( i_cfg, NUM_CFG_IF,
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
    #endif

    on tile[0]: filler(0x77);

    #else

    on tile[0]: mii_ethernet_mac(i_cfg, NUM_CFG_IF,
                                 i_rx_lp, NUM_RX_LP_IF,
                                 i_tx_lp, NUM_TX_LP_IF,
                                 p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                 p_eth_txclk, p_eth_txen, p_eth_txd,
                                 p_eth_dummy,
                                 eth_rxclk, eth_txclk,
                                 1600);
    on tile[0]: filler(0x44);

    #endif // RT
    on tile[RT]: test_task(i_cfg[2], i_rx_lp[2], 0x3333, 0, i_ctrl[2]);
    on tile[RT]: test_task(i_cfg[3], i_rx_lp[3], 0x4444, 0, i_ctrl[3]);

    #endif // RGMII

    on tile[0]: test_task(i_cfg[0], i_rx_lp[0], 0x1111, 1, i_ctrl[0]);
    on tile[0]: test_task(i_cfg[1], i_rx_lp[1], 0x2222, 1, i_ctrl[1]);

    on tile[0]: control(p_test_ctrl, i_ctrl, NUM_CFG_IF, NUM_CFG_IF);
  }
  return 0;
}
