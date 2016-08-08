// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#include "ports.h"

port p_ctrl = on tile[0]: XS1_PORT_1A;
#include "control.xc"

#include "helpers.xc"

/* Tests that the appdata word registered with the filter gets returned to the
 * user correctly when a packet is received.
 */
void test_task(client ethernet_cfg_if cfg,
               client ethernet_rx_if rx,
               streaming chanend ?rx_hp,
               uint16_t etype,
               client control_if ctrl)
{
  unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
  ethernet_packet_info_t packet_info;
  ethernet_macaddr_filter_t macaddr_filter;
  timer tmr;
  unsigned t;
  tmr :> t;
  macaddr_filter.appdata = etype;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;

  size_t index = rx.get_index();
  macaddr_filter.addr[5] = index;

  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  if (ETHERNET_SUPPORT_HP_QUEUES && !isnull(rx_hp)) {
    macaddr_filter.addr[5] = 7;
    macaddr_filter.appdata += 1;
    cfg.add_macaddr_filter(0, 1, macaddr_filter);
  }

  cfg.add_ethertype_filter(index, etype);

  int done = 0;
  while (!done) {
    select {
      case !isnull(rx_hp) => ethernet_receive_hp_packet(rx_hp, rxbuf, packet_info):
      debug_printf("%d: Received HP packet, type=%d, len=%d, appdata=%x.\n",
                   index + 1,
                   packet_info.type, packet_info.len, packet_info.filter_data);
      break;
    case rx.packet_ready():
      rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);
      debug_printf("%d: Received packet, type=%d, len=%d, appdata=%x.\n",
                   index + 1,
                   packet_info.type, packet_info.len, packet_info.filter_data);
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
  streaming chan c_rx_hp;

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

    #else // RGMII

    #if RT

    on tile[0]: mii_ethernet_rt_mac(i_cfg, NUM_CFG_IF,
                                    i_rx_lp, NUM_RX_LP_IF,
                                    i_tx_lp, NUM_TX_LP_IF,
                                    c_rx_hp, null,
                                    p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                    p_eth_txclk, p_eth_txen, p_eth_txd,
                                    eth_rxclk, eth_txclk,
                                    4000, 4000, ETHERNET_DISABLE_SHAPER);
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
    #endif // RGMII

    on tile[0]: test_task(i_cfg[0], i_rx_lp[0], null, 0x1111, i_ctrl[0]);
    on tile[0]: test_task(i_cfg[1], i_rx_lp[1], null, 0x2222, i_ctrl[1]);
    on tile[RT]: test_task(i_cfg[2], i_rx_lp[2], c_rx_hp, 0x3333, i_ctrl[2]);
    on tile[RT]: test_task(i_cfg[3], i_rx_lp[3], null, 0x4444, i_ctrl[3]);

    on tile[0]: control(p_ctrl, i_ctrl, NUM_CFG_IF, NUM_CFG_IF);
  }
  return 0;
}
