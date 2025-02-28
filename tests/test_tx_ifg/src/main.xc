// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "helpers.xc"

#if RMII
#include "ports_rmii.h"
#else
#include "ports.h"
#endif
#include "log_tx_ts.h"

void test_tx_sweep(client ethernet_tx_if tx, streaming chanend ? c_tx_hp)
{
  // Send a burst of frames to test the TX performance of the MAC layer and buffering
  // Just repeat the same frame numerous times to eliminate the frame setup time

  char data[ETHERNET_MAX_PACKET_SIZE];

  const int header_bytes = 14;

  // src/dst MAC addresses
  size_t j = 0;
  for (; j < 12; j++)
    data[j] = j;

  // Populate the packet with known data
  int x = 0;
  const int step = 10;
  for (; j < ETHERNET_MAX_PACKET_SIZE; j++) {
    x += step;
    data[j] = x;
  }

  while (1) {
    for(unsigned length=60; length<=1514; length++)
    {
      // Send a valid length in the ether len/type field
      data[12] = (length - header_bytes) >> 8;
      data[13] = (length - header_bytes) & 0xff;
      for(unsigned i=0; i<2; i++) // Restricting to 2 packets for each frame size. Takes about 15mins to run on sim.
      {
        if (isnull(c_tx_hp)) {
          tx.send_packet(data, length, ETHERNET_ALL_INTERFACES);
        }
        else {
          ethernet_send_hp_packet(c_tx_hp, data, length, ETHERNET_ALL_INTERFACES);
        }
      }
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

    #if ETHERNET_SUPPORT_HP_QUEUES
    on tile[0]: test_tx_sweep(i_tx_lp[0], c_tx_hp);
    #else
    on tile[0]: test_tx_sweep(i_tx_lp[0], null);
    #endif

    #else // RGMII

    #if RT

    #if MII
      on tile[0]: mii_ethernet_rt_mac(i_cfg, NUM_CFG_IF,
                                      i_rx_lp, NUM_RX_LP_IF,
                                      i_tx_lp, NUM_TX_LP_IF,
                                      c_rx_hp, c_tx_hp,
                                      p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                      p_eth_txclk, p_eth_txen, p_eth_txd,
                                      eth_rxclk, eth_txclk,
                                      4000, 4000, ETHERNET_DISABLE_SHAPER);
    #elif RMII
      on tile[0]: rmii_ethernet_rt_mac(i_cfg, NUM_CFG_IF,
                                      i_rx_lp, NUM_RX_LP_IF,
                                      i_tx_lp, NUM_TX_LP_IF,
                                      c_rx_hp, c_tx_hp,
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
#if PROBE_TX_TIMESTAMPS
    on tile[0]: tx_timestamp_probe();
#endif
    #endif

    #if ETHERNET_SUPPORT_HP_QUEUES
    on tile[1]: test_tx_sweep(i_tx_lp[0], c_tx_hp);
    #else
    on tile[1]: test_tx_sweep(i_tx_lp[0], null);
    #endif

    #else
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

    on tile[0]: test_tx_sweep(i_tx_lp[0], null);

    #endif // RT
    #endif // RGMII

  }
  return 0;
}
