// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "helpers.xc"

#include "ports.h"
port p_test_ctrl = on tile[0]: XS1_PORT_1C;

struct test_packet { int len; int step; int tagged; }
test_packets[] =
  {
    { 60, 1, 0 },
    { ETHERNET_MAX_PACKET_SIZE, 5, 0 },
    { 60, 1, 1 },
    { ETHERNET_MAX_PACKET_SIZE, 5, 1 },
  };

void test_tx(client ethernet_tx_if tx, streaming chanend ? c_tx_hp)
{
  p_test_ctrl <: 0;
  for (int i = 0; i < sizeof(test_packets)/sizeof(test_packets[0]); i++) {
    char data[ETHERNET_MAX_PACKET_SIZE];

    // src/dst MAC addresses
    size_t j = 0;
    for (; j < 12; j++)
      data[j] = j;

    int len = test_packets[i].len - 14;

    if (test_packets[i].tagged) {
      data[j++] = 0x81;
      data[j++] = 0x00;
      data[j++] = 0x00;
      data[j++] = 0x00;

      // There will be 4 less data bytes with the VLAN/Priority tag
      len -= 4;
    }

    data[j++] = len >> 8;
    data[j++] = len & 0xff;

    int x = 0;
    for (; j < test_packets[i].len; j++) {
      x += test_packets[i].step;
      data[j] = x;
    }

    if (isnull(c_tx_hp)) {
      tx.send_packet(data, test_packets[i].len, ETHERNET_ALL_INTERFACES);
    }
    else {
      ethernet_send_hp_packet(c_tx_hp, data, test_packets[i].len, ETHERNET_ALL_INTERFACES);
    }
  }

  // Give time for the packet to start to be sent in the case of the RT MAC
  timer t;
  int time;
  t :> time;
  t when timerafter(time + 5000) :> time;

  // Signal that all packets have been sent
  p_test_ctrl <: 1;
}

#define NUM_CFG_IF 1
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];

  #if ETHERNET_SUPPORT_HP_QUEUES
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

    on tile[0]: {
      // Give time for the MAC layer to detect the speed of the PHY and set itself up
      timer t;
      int time;
      t :> time;
      t when timerafter(time + 5000) :> time;

      #if ETHERNET_SUPPORT_HP_QUEUES
      test_tx(i_tx_lp[0], c_tx_hp);
      #else
      test_tx(i_tx_lp[0], null);
      #endif
    }

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
    on tile[0]: filler(0x2222);
    on tile[0]: filler(0x3333);

    #if ETHERNET_SUPPORT_HP_QUEUES
    on tile[0]: test_tx(i_tx_lp[0], c_tx_hp);
    #else
    on tile[0]: test_tx(i_tx_lp[0], null);
    #endif

    #else // RT
    on tile[0]: mii_ethernet_mac(i_cfg, NUM_CFG_IF,
                                 i_rx_lp, NUM_RX_LP_IF,
                                 i_tx_lp, NUM_TX_LP_IF,
                                 p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                 p_eth_txclk, p_eth_txen, p_eth_txd,
                                 p_eth_dummy,
                                 eth_rxclk, eth_txclk,
                                 1600);
    on tile[0]: filler(0x1111);
    on tile[0]: filler(0x2222);
    on tile[0]: filler(0x3333);
    on tile[0]: filler(0x4444);
    on tile[0]: filler(0x5555);

    on tile[0]: test_tx(i_tx_lp[0], null);

    #endif // RT
    #endif // RGMII

  }
  return 0;
}
