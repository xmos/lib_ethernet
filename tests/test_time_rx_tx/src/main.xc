// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>
#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "xta_test_pragmas.h"
#include "debug_print.h"
#include "syscall.h"
#include "helpers.xc"

typedef enum {
  STATUS_ACTIVE,
  STATUS_DONE
} status_t;

typedef interface control_if {
  [[notification]] slave void status_changed();
  [[clears_notification]] void get_status(status_t &status);
} control_if;

port p_smi_mdio   = on tile[0]: XS1_PORT_1M;
port p_smi_mdc    = on tile[0]: XS1_PORT_1N;
port p_eth_rxclk  = on tile[0]: XS1_PORT_1J;
port p_eth_rxd    = on tile[0]: XS1_PORT_4E;
port p_eth_txd    = on tile[0]: XS1_PORT_4F;
port p_eth_rxdv   = on tile[0]: XS1_PORT_1K;
port p_eth_txen   = on tile[0]: XS1_PORT_1L;
port p_eth_txclk  = on tile[0]: XS1_PORT_1I;
port p_eth_int    = on tile[0]: XS1_PORT_1O;
port p_eth_rxerr  = on tile[0]: XS1_PORT_1P;
port p_eth_dummy  = on tile[0]: XS1_PORT_8C;

port p_ctrl       = on tile[0]: XS1_PORT_1C;

clock eth_rxclk   = on tile[0]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[0]: XS1_CLKBLK_2;

#define NUM_PACKET_LENGTHS 64

void test_tx(client ethernet_if eth)
{
  // Send a burst of frames to test the TX performance of the MAC layer and buffering
  // Just repeat the same frame numerous times to eliminate the frame setup time

  char data[ETHERNET_MAX_PACKET_SIZE];
  int lengths[NUM_PACKET_LENGTHS];

  const int header_bytes = 14;

  // Choose random packet lengths (but there must at least be a header)
  const int min_data_bytes = header_bytes;
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
    data[j] = j;

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
      eth.send_packet(data, length, ETHERNET_ALL_INTERFACES);
    }
  }
}

void test_rx(client ethernet_if eth, client control_if ctrl)
{
  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.vlan = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;
  eth.add_macaddr_filter(macaddr_filter);

  int num_bytes = 0;
  int done = 0;
  while (!done) {
    #pragma ordered
    select {
    case eth.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      eth.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);
      num_bytes += packet_info.len;
      break;

    case ctrl.status_changed():
      status_t status;
      ctrl.get_status(status);
      if (status == STATUS_DONE)
        done = 1;
      break;
    }
  }
  debug_printf("Received %d bytes\n", num_bytes);
  while (1) {
    // Wait for the test to be terminated by testbench
  }
}

void control(port p_ctrl, server control_if ctrl)
{
  int tmp;
  status_t current_status = STATUS_ACTIVE;

  while (1) {
    select {
    case current_status != STATUS_DONE => p_ctrl when pinseq(1) :> tmp:
      current_status = STATUS_DONE;
      ctrl.status_changed();
      break;
    case ctrl.get_status(status_t &status):
      status = current_status;
      break;
    }
  }
}

#define ETH_RX_BUFFER_SIZE_WORDS 1600

int main()
{
  ethernet_if i_eth[2];
  control_if i_ctrl;
  
  par {
    #if RT
    on tile[0]: mii_ethernet_rt(i_eth, 2,
                                p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                p_eth_txclk, p_eth_txen, p_eth_txd,
                                eth_rxclk, eth_txclk,
                                2000, 2000, 2000, 2000, 1);
    on tile[0]: filler(0x88);

    #else
    on tile[0]: mii_ethernet(i_eth, 2,
                             p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                             p_eth_txclk, p_eth_txen, p_eth_txd,
                             p_eth_dummy,
                             eth_rxclk, eth_txclk,
                             ETH_RX_BUFFER_SIZE_WORDS);
    on tile[0]: filler(0x88);
    on tile[0]: filler(0x99);
    on tile[0]: filler(0xaa);

    #endif

    on tile[0]: test_tx(i_eth[0]);
    on tile[0]: test_rx(i_eth[1], i_ctrl);
    on tile[0]: control(p_ctrl, i_ctrl);
  }
  return 0;
}
