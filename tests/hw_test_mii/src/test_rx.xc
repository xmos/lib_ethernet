// Copyright 2013-2021 XMOS LIMITED.
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

#define NUM_TS_LOGS (1000) // Save the first 5000 timestamp logs to get an idea of the general IFG gap
#define NUM_SEQ_ID_MISMATCH_LOGS (1000) // Save the first few seq id mismatches

#define PRINT_TS_LOG (0)

typedef struct
{
  unsigned current_seq_id;
  unsigned prev_seq_id;
  unsigned ifg;
}seq_id_pair_t;

void test_rx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 unsigned client_num,
                 chanend c_xscope_control)
{
  set_core_fast_mode_on();
  ethernet_macaddr_filter_t macaddr_filter;
  unsigned char host_mac_addr[MACADDR_NUM_BYTES];

  macaddr_filter.appdata = 0;
  for (int i = 0; i < MACADDR_NUM_BYTES; i++)
    macaddr_filter.addr[i] = i+client_num;

  size_t index = rx.get_index();
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  // Add broadcast filter
  memset(macaddr_filter.addr, 0xff, MACADDR_NUM_BYTES);
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  cfg.add_ethertype_filter(index, 0x2222);

  debug_printf("Test started\n");
  unsigned pkt_count = 0;
  unsigned num_rx_bytes = 0;
  uint8_t broadcast[MACADDR_NUM_BYTES];
  for(int i=0; i<MACADDR_NUM_BYTES; i++)
  {
    broadcast[i] = 0xff;
  }
  unsigned enable_time_based_check = 0;
  timer t;
  unsigned time;
  t :> time;
  unsigned test_end_time;
  unsigned done = 0;
  unsigned dut_timeout_s = 10; // dut timeout in seconds

  unsigned timestamps[NUM_TS_LOGS];
  seq_id_pair_t seq_id_err_log[NUM_SEQ_ID_MISMATCH_LOGS];

  unsigned counter = 0;
  unsigned count_seq_id_err_log = 0;
  unsigned count_seq_id_mismatch = 0;
  unsigned total_missing = 0;
  unsigned prev_seq_id, prev_timestamp;
  unsigned max_ifg = 0, min_ifg = 10000000; // Max and min observed IFG in reference
  unsigned receiving = 1;

  unsigned test_fail=0;

  while (!done)
  {
    select {
      case receiving => rx.packet_ready():
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

#if LOOPBACK
        uint8_t dst_mac[MACADDR_NUM_BYTES], src_mac[MACADDR_NUM_BYTES];
        memcpy(dst_mac, rxbuf, MACADDR_NUM_BYTES);
        memcpy(src_mac, rxbuf+MACADDR_NUM_BYTES, MACADDR_NUM_BYTES);

        // swap src and dst mac addr
        memcpy(rxbuf, src_mac, MACADDR_NUM_BYTES);
        memcpy(rxbuf+MACADDR_NUM_BYTES, dst_mac, MACADDR_NUM_BYTES);
        tx.send_packet(rxbuf, packet_info.len, ETHERNET_ALL_INTERFACES);
#endif

        if(pkt_count == 0)
        {
          enable_time_based_check = 1;
          t :> time;
          test_end_time = time + (dut_timeout_s * XS1_TIMER_HZ);
        }

        if((pkt_count >= 0) && (pkt_count < 0 + NUM_TS_LOGS))
        {
          timestamps[counter] = timestamp;
          counter += 1;
        }

        pkt_count += 1;
        num_rx_bytes += packet_info.len;

        if(pkt_count > 1)
        {
          // Calculate IFG
          unsigned ifg;
          if(timestamp > prev_timestamp)
          {
            ifg = (unsigned)(timestamp-prev_timestamp);
          }
          else
          {
            ifg = ((unsigned)(0xffffffff) - prev_timestamp) + timestamp;
          }
          if(ifg > max_ifg)
          {
            max_ifg = ifg;
          }
          else if(ifg < min_ifg)
          {
            min_ifg = ifg;
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
              seq_id_err_log[count_seq_id_err_log].ifg = ifg;
              count_seq_id_err_log += 1;
              total_missing += (seq_id - prev_seq_id - 1);
            }
            count_seq_id_mismatch += 1;
          }
        }
        prev_seq_id = seq_id;
        prev_timestamp = timestamp;
        break;
#if ENABLE_DUT_TIMEOUT
      case (enable_time_based_check == 1) => t when timerafter(test_end_time) :> test_end_time:
        done = 1;
        break;
#endif
      case c_xscope_control :> int cmd: // Shutdown received over xscope
        if(cmd == CMD_DEVICE_CONNECT)
        {
            c_xscope_control <: 1; // Indicate ready
        }
        else if(cmd == CMD_DEVICE_SHUTDOWN)
        {
          done = 1;
        }
        else if(cmd == CMD_SET_DEVICE_MACADDR)
        {
          debug_printf("Received CMD_SET_DEVICE_MACADDR command\n");
          for(int i=0; i<6; i++)
          {
            c_xscope_control :> macaddr_filter.addr[i];
            cfg.add_macaddr_filter(index, 0, macaddr_filter);
          }
          c_xscope_control <: 1; // Acknowledge
        }
        else if(cmd == CMD_SET_HOST_MACADDR)
        {
          debug_printf("Received CMD_SET_HOST_MACADDR command\n");
          for(int i=0; i<6; i++)
          {
            c_xscope_control :> host_mac_addr[i]; // host_mac_addr won't be used since this is an rx/loopback client
          }
          c_xscope_control <: 1; // Acknowledge
        }
        else if(cmd == CMD_SET_DUT_RECEIVE)
        {
          c_xscope_control :> receiving;
          c_xscope_control <: 1; // Acknowledge
        }
        else if(cmd == CMD_EXIT_DEVICE_MAC)
        {
          debug_printf("Received CMD_EXIT_DEVICE_MAC command\n");
          cfg.exit();
          // the client is expected to exit after signalling the Mac to exit
          done = 1;
        }
        break;
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
  debug_printf("DUT client index %u: counter = %u, min_ifg = %u, max_ifg = %u\n", client_num, counter, min_ifg, max_ifg);
  debug_printf("DUT client index %u: Received %d bytes, %d packets\n", client_num, num_rx_bytes, pkt_count);

  if(test_fail)
  {
    debug_printf("DUT client index %u ERROR: Test failed due to sequence ID mismatch. Total %u seq_id mismatches. Total missing %u packets\n", client_num, count_seq_id_mismatch, total_missing);
    debug_printf("printing the first %u mismatches\n", count_seq_id_err_log);
    for(int i=0; i<count_seq_id_err_log; i++)
    {
      unsigned diff = seq_id_err_log[i].current_seq_id - seq_id_err_log[i].prev_seq_id - 1;
      debug_printf("(current_seq_id, prev_seq_id) = (%u, %u). Missing %u packets. IFG = %u\n", seq_id_err_log[i].current_seq_id, seq_id_err_log[i].prev_seq_id, diff, seq_id_err_log[i].ifg);
    }
  }
  c_xscope_control <: 1; // Acknowledge CMD_DEVICE_SHUTDOWN
}



void test_rx_hp(client ethernet_cfg_if cfg,
                streaming chanend c_rx_hp,
                unsigned client_num,
                chanend c_xscope_control)
{
  set_core_fast_mode_on();

  ethernet_macaddr_filter_t macaddr_filter;
  unsigned char host_mac_addr[MACADDR_NUM_BYTES];

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i+client_num;
  cfg.add_macaddr_filter(0, 1, macaddr_filter);

  unsigned num_rx_bytes = 0;
  unsigned pkt_count = 0;
  int done = 0;
  unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
  seq_id_pair_t seq_id_err_log[NUM_SEQ_ID_MISMATCH_LOGS];

  unsigned count_seq_id_err_log = 0;
  unsigned count_seq_id_mismatch = 0;
  unsigned total_missing = 0;
  unsigned prev_seq_id;

  unsigned test_fail=0;

  while (!done) {
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

      case c_xscope_control :> int cmd: // Shutdown received over xscope
        if(cmd == CMD_DEVICE_CONNECT)
        {
            c_xscope_control <: 1; // Indicate ready
        }
        else if(cmd == CMD_DEVICE_SHUTDOWN)
        {
          done = 1;
        }
        else if(cmd == CMD_SET_DEVICE_MACADDR)
        {
          debug_printf("Received CMD_SET_DEVICE_MACADDR command\n");
          for(int i=0; i<6; i++)
          {
            c_xscope_control :> macaddr_filter.addr[i];
            cfg.add_macaddr_filter(0, 1, macaddr_filter);
          }
          c_xscope_control <: 1; // Acknowledge
        }
        else if(cmd == CMD_SET_HOST_MACADDR)
        {
          debug_printf("Received CMD_SET_HOST_MACADDR command\n");
          for(int i=0; i<6; i++)
          {
            c_xscope_control :> host_mac_addr[i]; // host_mac_addr won't be used since this is an rx/loopback client
          }
          c_xscope_control <: 1; // Acknowledge
        }
        else if(cmd == CMD_SET_DUT_RECEIVE)
        {
          c_xscope_control :> int temp; // This shouldn't be sent for a HP client
          c_xscope_control <: 1; // Acknowledge
        }
        else if(cmd == CMD_EXIT_DEVICE_MAC)
        {
          cfg.exit();
          // the client is expected to exit after signalling the Mac to exit
          done = 1;
        }
        break;
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
