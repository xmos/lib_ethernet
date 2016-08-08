// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "helpers.xc"

#include "ports.h"
port p_test_ctrl = on tile[0]: XS1_PORT_1C;

#define PACKET_BYTES 100
#define PACKET_WORDS ((PACKET_BYTES+3)/4)

#define VLAN_TAGGED 1

#define MII_CREDIT_FRACTIONAL_BITS 16

static int calc_idle_slope(int bps)
{
  long long slope = ((long long) bps) << (MII_CREDIT_FRACTIONAL_BITS);
  slope = slope / 100000000;

  return (int) slope;
}

void hp_traffic(client ethernet_cfg_if i_cfg, streaming chanend c_tx_hp)
{
  // Request 5MB/s
  i_cfg.set_egress_qav_idle_slope(0, calc_idle_slope(5 * 1024 * 1024));
  
  // Indicate the test is not yet complete
  p_test_ctrl <: 0;
  
  unsigned data[PACKET_WORDS];
  for (size_t i = 0; i < PACKET_WORDS; i++) {
    data[i] = i;
  }
  
  // src/dst MAC addresses
  size_t j = 0;
  for (; j < 12; j++)
    ((char*)data)[j] = j;

  if (VLAN_TAGGED) {
    ((char*)data)[j++] = 0x81;
    ((char*)data)[j++] = 0x00;
    ((char*)data)[j++] = 0x00;
    ((char*)data)[j++] = 0x00;
  }

  const int length = PACKET_BYTES;
  const int header_bytes = VLAN_TAGGED ? 18 : 14;
  ((char*)data)[j++] = (length - header_bytes) >> 8;
  ((char*)data)[j++] = (length - header_bytes) & 0xff;

  while (1) {
    ethernet_send_hp_packet(c_tx_hp, (char *)data, length, ETHERNET_ALL_INTERFACES);
  }

  // Give time for the packet to start to be sent in the case of the RT MAC
  timer t;
  int time;
  t :> time;
  t when timerafter(time + 5000) :> time;

  // Signal that all packets have been sent
  p_test_ctrl <: 1;
}

#define NUM_PACKET_LENGTHS 64

#if CLK_125
#define MAX_INTER_PACKET_DELAY 0xf
#else
#define MAX_INTER_PACKET_DELAY 0x3f
#endif

void lp_traffic(client ethernet_tx_if tx)
{
  // Send a burst of frames to test the TX performance of the MAC layer and buffering
  // Just repeat the same frame numerous times to eliminate the frame setup time

  char data[ETHERNET_MAX_PACKET_SIZE];
  int lengths[NUM_PACKET_LENGTHS];

  const int header_bytes = 14;

  // Choose random packet lengths:
  //  - there must at least be a header in order not to crash this application
  //  - there must also be 46 bytes of payload to produce valid minimum sized
  //    frames
  const int min_data_bytes = header_bytes + 46;
  random_generator_t rand = random_create_generator_from_seed(1);
  for (int i = 0; i < NUM_PACKET_LENGTHS; i++) {
    int do_small_packet = (random_get_random_number(rand) & 0xff) > 50;
    if (do_small_packet)
      lengths[i] = random_get_random_number(rand) % (100 - min_data_bytes);
    else
      lengths[i] = random_get_random_number(rand) % (ETHERNET_MAX_PACKET_SIZE - min_data_bytes);

    lengths[i] += min_data_bytes;
  }

  // src/dst MAC addresses
  size_t j = 0;
  for (; j < 12; j++)
    data[j] = j + 1;

  // Populate the packet with known data
  int x = 0;
  const int step = 10;
  for (; j < ETHERNET_MAX_PACKET_SIZE; j++) {
    x += step;
    data[j] = x;
  }

  while (1) {
    int do_burst = (random_get_random_number(rand) & 0xff) > 200;
    int len_index = random_get_random_number(rand) & (NUM_PACKET_LENGTHS - 1);
    int burst_len = 1;

    if (do_burst) {
      burst_len = random_get_random_number(rand) & 0xf;
    }

    for (int i = 0; i < burst_len; i++) {
      int length = lengths[len_index];

      // Send a valid length in the ether len/type field
      data[12] = (length - header_bytes) >> 8;
      data[13] = (length - header_bytes) & 0xff;

      tx.send_packet(data, length, ETHERNET_ALL_INTERFACES);
    }
    
    int delay = random_get_random_number(rand) % MAX_INTER_PACKET_DELAY;
    delay_microseconds(delay);
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
  streaming chan c_tx_hp;

#if RGMII
  streaming chan c_rgmii_cfg;
#endif

  par {
    #if RGMII

    on tile[1]: rgmii_ethernet_mac(i_rx_lp, NUM_RX_LP_IF,
                                   i_tx_lp, NUM_TX_LP_IF,
                                   null, c_tx_hp,
                                   c_rgmii_cfg,
                                   rgmii_ports,
                                   ETHERNET_ENABLE_SHAPER);
    on tile[1]: rgmii_ethernet_mac_config(i_cfg, NUM_CFG_IF, c_rgmii_cfg);

    on tile[0]: {
      // Give time for the MAC layer to detect the speed of the PHY and set itself up
      timer t;
      int time;
      t :> time;
      t when timerafter(time + 5000) :> time;

      par {
        hp_traffic(i_cfg[0], c_tx_hp);
        lp_traffic(i_tx_lp[0]);
      }
    }

    #else // RGMII

    on tile[0]: mii_ethernet_rt_mac(i_cfg, NUM_CFG_IF,
                                    i_rx_lp, NUM_RX_LP_IF,
                                    i_tx_lp, NUM_TX_LP_IF,
                                    null, c_tx_hp,
                                    p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                    p_eth_txclk, p_eth_txen, p_eth_txd,
                                    eth_rxclk, eth_txclk,
                                    4000, 4000, ETHERNET_ENABLE_SHAPER);
    on tile[0]: filler(0x1111);
    on tile[0]: filler(0x3333);

    on tile[0]: hp_traffic(i_cfg[0], c_tx_hp);
    on tile[0]: lp_traffic(i_tx_lp[0]);

    #endif // RGMII

  }
  return 0;
}
