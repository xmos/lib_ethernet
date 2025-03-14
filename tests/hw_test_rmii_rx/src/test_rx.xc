// Copyright 2013-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <debug_print.h>
#include <xclib.h>
#include <stdint.h>
#include <stdlib.h>
#include <ethernet.h>
#include <otp_board_info.h>
#include <string.h>
#include <print.h>
#include "test_rx.h"
#include "xscope_control.h"
#include "xscope_cmd_handler.h"

#define NUM_TS_LOGS (1000) // Save the first 5000 timestamp logs to get an idea of the general IFG gap
#define NUM_SEQ_ID_MISMATCH_LOGS (1000) // Save the first few seq id mismatches

#define PRINT_TS_LOG (0)

typedef struct
{
  unsigned current_seq_id;
  unsigned prev_seq_id;
  unsigned rx_ts_diff;
}seq_id_pair_t;

void test_rx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 unsigned client_num,
                 chanend c_xscope_control)
{
  set_core_fast_mode_on();
  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < MACADDR_NUM_BYTES; i++)
    macaddr_filter.addr[i] = i+client_num;

  size_t index = rx.get_index();
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  // Add broadcast filter
  memset(macaddr_filter.addr, 0xff, MACADDR_NUM_BYTES);
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  debug_printf("Test started\n");
  unsigned pkt_count = 0;
  unsigned num_rx_bytes = 0;
  uint8_t broadcast[MACADDR_NUM_BYTES];
  for(int i=0; i<MACADDR_NUM_BYTES; i++)
  {
    broadcast[i] = 0xff;
  }

  unsigned timestamps[NUM_TS_LOGS];
  seq_id_pair_t seq_id_err_log[NUM_SEQ_ID_MISMATCH_LOGS];

  unsigned counter = 0;
  unsigned count_seq_id_err_log = 0;
  unsigned count_seq_id_mismatch = 0;
  unsigned total_missing = 0;
  unsigned prev_seq_id, prev_timestamp;
  // Log max and min of RX timestamp difference between consecutive packets.
  // To convert from timestamp diff to IFG, do,
  // rx_ts_diff - (packet_length_without_crc_and_preamble_of_the_first_packet_bits + crc_bits + preamble_bits)
  // For example, for a 1514 byte packet, IFG = rx_ts_diff - ((1514+4+8)*8)
  unsigned max_rx_ts_diff = 0, min_rx_ts_diff = 10000000; // Max and min observed IFG in reference

  unsigned test_fail=0;

  // Initialise client_state
  client_state_t client_state;
  memset(&client_state, 0, sizeof(client_state));
  client_state.receiving = 1; // Set to start receiving by default

  // Initialise client cfg
  client_cfg_t client_cfg;
  client_cfg.client_num = client_num;
  client_cfg.client_index = index;
  client_cfg.is_hp = 0;

  while (!client_state.done)
  {
    select {
      case client_state.receiving => rx.packet_ready():
        unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
        ethernet_packet_info_t packet_info;
        rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);

        if (packet_info.type != ETH_DATA) {
          continue;
        }

        // Get seq_id of the current packet
        unsigned seq_id = ((unsigned)rxbuf[14] << 24) | ((unsigned)rxbuf[15] << 16) | ((unsigned)rxbuf[16] << 8) | (unsigned)rxbuf[17];
        unsigned timestamp = packet_info.timestamp;
        //printhexln((unsigned)seq_id);

#if PRINT_TS_LOG
        if((pkt_count >= 0) && (pkt_count < 0 + NUM_TS_LOGS))
        {
          timestamps[counter] = timestamp;
          counter += 1;
        }
#endif
        pkt_count += 1;
        num_rx_bytes += packet_info.len;

        if(pkt_count > 1)
        {
          // Calculate IFG
          unsigned rx_ts_diff;
          if(timestamp > prev_timestamp)
          {
            rx_ts_diff = (unsigned)(timestamp-prev_timestamp);
          }
          else
          {
            rx_ts_diff = ((unsigned)(0xffffffff) - prev_timestamp) + timestamp;
          }
          if(rx_ts_diff > max_rx_ts_diff)
          {
            max_rx_ts_diff = rx_ts_diff;
          }
          else if(rx_ts_diff < min_rx_ts_diff)
          {
            min_rx_ts_diff = rx_ts_diff;
          }

          // Check for seq id
          if(!(seq_id == prev_seq_id + 1) && !(seq_id == prev_seq_id)) // Consider seq_id == prev_seq_id okay in order to test the same frame sent in a loop by the host. No seq id check req in this case
          {
            test_fail = 1;
            // Any debug printing here will mess up timing. also, wouldn't work in case of multiple threads printing. Save a few fail cases to print later
            if(count_seq_id_err_log < NUM_SEQ_ID_MISMATCH_LOGS)
            {
              seq_id_err_log[count_seq_id_err_log].current_seq_id = seq_id;
              seq_id_err_log[count_seq_id_err_log].prev_seq_id = prev_seq_id;
              seq_id_err_log[count_seq_id_err_log].rx_ts_diff = rx_ts_diff;
              count_seq_id_err_log += 1;
              total_missing += (seq_id - prev_seq_id - 1);
            }
            count_seq_id_mismatch += 1;
          }
        }
        prev_seq_id = seq_id;
        prev_timestamp = timestamp;
        break;

      case xscope_cmd_handler (c_xscope_control, client_cfg, cfg, client_state );

    } // select
  }

#if PRINT_TS_LOG
  unsigned print_pkt_count = (pkt_count > NUM_TS_LOGS) ? NUM_TS_LOGS : pkt_count;

  if(print_pkt_count >= 2)
  {
    for(int i=0; i<print_pkt_count-1; i++)
    {
      unsigned diff;
      if(timestamps[i+1] > timestamps[i])
      {
        diff = (unsigned)(timestamps[i+1]-timestamps[i]);
      }
      else
      {
        diff = ((unsigned)(0xffffffff) - timestamps[i]) + timestamps[i+1];
      }
      debug_printf("client %u: i=%d, ts_diff=%u, ts=(%u, %u)\n", client_num,  i, (unsigned)diff, timestamps[i+1], timestamps[i] );
    }
  }
#endif
  debug_printf("DUT client index %u: counter = %u, min_rx_ts_diff = %u, max_rx_ts_diff = %u\n", client_num, counter, min_rx_ts_diff, max_rx_ts_diff);
  debug_printf("DUT client index %u: Received %d bytes, %d packets\n", client_num, num_rx_bytes, pkt_count);

  if(test_fail)
  {
    debug_printf("DUT client index %u ERROR: Test failed due to sequence ID mismatch. Total %u seq_id mismatches. Total missing %u packets\n", client_num, count_seq_id_mismatch, total_missing);
    debug_printf("printing the first %u mismatches\n", count_seq_id_err_log);
    for(int i=0; i<count_seq_id_err_log; i++)
    {
      unsigned diff = seq_id_err_log[i].current_seq_id - seq_id_err_log[i].prev_seq_id - 1;
      debug_printf("(current_seq_id, prev_seq_id) = (%u, %u). Missing %u packets. IFG = %u\n", seq_id_err_log[i].current_seq_id, seq_id_err_log[i].prev_seq_id, diff, seq_id_err_log[i].rx_ts_diff);
    }
  }
  c_xscope_control <: 1; // Acknowledge CMD_DEVICE_SHUTDOWN
  wait_us(2000); // Since this task might be scheduled in a while(1), wait sometime before exiting so that xscope_control exits first in case of a shutdown command.
                 // Shutdown fails occasionally (To be debugged) otherwise.
}


void test_rx_hp(client ethernet_cfg_if cfg,
                streaming chanend c_rx_hp,
                unsigned client_num,
                chanend c_xscope_control)
{
  set_core_fast_mode_on();

  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i+client_num;
  cfg.add_macaddr_filter(0, 1, macaddr_filter);

  unsigned num_rx_bytes = 0;
  unsigned pkt_count = 0;
  unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
  seq_id_pair_t seq_id_err_log[NUM_SEQ_ID_MISMATCH_LOGS];

  unsigned count_seq_id_err_log = 0;
  unsigned count_seq_id_mismatch = 0;
  unsigned total_missing = 0;
  unsigned prev_seq_id;

  unsigned test_fail=0;
  // Initialise client_state
  client_state_t client_state;
  memset(&client_state, 0, sizeof(client_state));
  client_state.receiving = 1; // Set to start receiving by default

  // Initialise client cfg
  client_cfg_t client_cfg;
  client_cfg.client_num = client_num;
  client_cfg.client_index = 0;
  client_cfg.is_hp = 1;

  while (!client_state.done) {
    ethernet_packet_info_t packet_info;

    #pragma ordered
    select {
      case ethernet_receive_hp_packet(c_rx_hp, rxbuf, packet_info):
        // Check the first byte after the header (which can be VLAN tagged)
        unsigned seq_id = ((unsigned)rxbuf[14] << 24) | ((unsigned)rxbuf[15] << 16) | ((unsigned)rxbuf[16] << 8) | (unsigned)rxbuf[17];
        // Check for seq id
        if(!(seq_id == prev_seq_id + 1) && !(seq_id == prev_seq_id)) // Consider seq_id == prev_seq_id okay in order to test the same frame sent in a loop by the host. No seq id check req in this case
        {
          test_fail = 1;
          // Any debug printing here will mess up timing. also, wouldn't work in case of multiple threads printing. Save a few fail cases to print later
          if(count_seq_id_err_log < NUM_SEQ_ID_MISMATCH_LOGS)
          {
            seq_id_err_log[count_seq_id_err_log].current_seq_id = seq_id;
            seq_id_err_log[count_seq_id_err_log].prev_seq_id = prev_seq_id;
            count_seq_id_err_log += 1;
            total_missing += (seq_id - prev_seq_id - 1);
          }
          count_seq_id_mismatch += 1;
        }
        pkt_count += 1;
        num_rx_bytes += packet_info.len;
        break;

      case xscope_cmd_handler (c_xscope_control, client_cfg, cfg, client_state );
    }
  }
  debug_printf("DUT client index %u: Received %d bytes, %d packets\n", client_num, num_rx_bytes, pkt_count);
  if(test_fail)
  {
    debug_printf("DUT client index %u ERROR: Test failed due to sequence ID mismatch. Total %u seq_id mismatches. Total missing %u packets\n", client_num, count_seq_id_mismatch, total_missing);
    debug_printf("printing the first %u mismatches\n", count_seq_id_err_log);
    for(int i=0; i<count_seq_id_err_log; i++)
    {
      unsigned diff = seq_id_err_log[i].current_seq_id - seq_id_err_log[i].prev_seq_id - 1;
      debug_printf("(current_seq_id, prev_seq_id) = (%u, %u). Missing %u packets\n", seq_id_err_log[i].current_seq_id, seq_id_err_log[i].prev_seq_id, diff);
    }
  }
  c_xscope_control <: 1; // Acknowledge CMD_DEVICE_SHUTDOWN
}
