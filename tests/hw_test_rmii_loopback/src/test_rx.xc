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
#include "test_loopback.h"
#include "xscope_control.h"
#include "xscope_cmd_handler.h"

#define NUM_TS_LOGS (1000) // Save the first 5000 timestamp logs to get an idea of the general IFG gap
#define NUM_SEQ_ID_MISMATCH_LOGS (1000) // Save the first few seq id mismatches

#define PRINT_TS_LOG (0)

typedef struct
{
  unsigned current_seq_id;
  unsigned prev_seq_id;
  unsigned ifg;
}seq_id_pair_t;

static void wait_us(int microseconds)
{
    timer t;
    unsigned time;

    t :> time;
    t when timerafter(time + (microseconds * 100)) :> void;
}


#define NUM_BUF 200
unsigned loopback_pkt_count = 0;
void test_rx_loopback(streaming chanend c_tx_hp,
                      client loopback_if i_loopback)
{
  set_core_fast_mode_on();

  unsafe {
    while (1) {
      unsigned len;
      uintptr_t buf;

      select {
      case i_loopback.packet_ready():
        i_loopback.get_packet(len, buf);
        break;
      }
      ethernet_send_hp_packet(c_tx_hp, (char *)buf, len, ETHERNET_ALL_INTERFACES);
      loopback_pkt_count += 1;
    }
  }
}

void test_rx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 unsigned client_num,
                 chanend c_xscope_control,
                 server loopback_if i_loopback)
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

#if PRINT_TS_LOG
  unsigned timestamps[NUM_TS_LOGS];
#endif
  seq_id_pair_t seq_id_err_log[NUM_SEQ_ID_MISMATCH_LOGS];

  unsigned counter = 0;
  unsigned count_seq_id_err_log = 0;
  unsigned count_seq_id_mismatch = 0;
  unsigned total_missing = 0;
  unsigned prev_seq_id, prev_timestamp;
  unsigned max_ifg = 0, min_ifg = 10000000; // Max and min observed IFG in reference

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

  unsigned char rxbuf[NUM_BUF][ETHERNET_MAX_PACKET_SIZE];
  unsigned rxlen[NUM_BUF];
  unsigned wr_index = 0;
  unsigned rd_index = 0;
  unsigned overflow = 0;

  while (!client_state.done)
  {
    select {
      case client_state.receiving => rx.packet_ready():
        ethernet_packet_info_t packet_info;
        rx.get_packet(packet_info, rxbuf[wr_index], ETHERNET_MAX_PACKET_SIZE);

        if (packet_info.type != ETH_DATA) {
          continue;
        }

        // Get seq_id of the current packet
        unsigned seq_id = ((unsigned)rxbuf[wr_index][14] << 24) | ((unsigned)rxbuf[wr_index][15] << 16) | ((unsigned)rxbuf[wr_index][16] << 8) | (unsigned)rxbuf[wr_index][17];
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

        if(!overflow)
        {
          uint8_t dst_mac[MACADDR_NUM_BYTES], src_mac[MACADDR_NUM_BYTES];
          memcpy(dst_mac, rxbuf[wr_index], MACADDR_NUM_BYTES);
          memcpy(src_mac, rxbuf[wr_index]+MACADDR_NUM_BYTES, MACADDR_NUM_BYTES);

          // swap src and dst mac addr
          memcpy(rxbuf[wr_index], src_mac, MACADDR_NUM_BYTES);
          memcpy(rxbuf[wr_index]+MACADDR_NUM_BYTES, dst_mac, MACADDR_NUM_BYTES);

            rxlen[wr_index] = packet_info.len;
            wr_index = (wr_index + 1) % NUM_BUF;
            if (wr_index == rd_index) {
                debug_printf("test_rx ran out of buffers. wr_index = %d, rd_index = %d\n", wr_index, rd_index);
                overflow = 1;
            }
            else
            {
                i_loopback.packet_ready();
            }
        }

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

      case i_loopback.get_packet(unsigned &len, uintptr_t &buf): {
        len = rxlen[rd_index];
        buf = (uintptr_t)&rxbuf[rd_index];
        rd_index = (rd_index + 1) % NUM_BUF;
        if (rd_index != wr_index)
        {
          i_loopback.packet_ready();
        }
        break;
      }

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
  debug_printf("DUT client index %u: counter = %u, min_ifg = %u, max_ifg = %u, overflow=%d, rd_index %d, wr_index %d\n", client_num, counter, min_ifg, max_ifg, overflow, rd_index, wr_index);
  debug_printf("DUT client index %u: Received %d bytes, %d packets\n", client_num, num_rx_bytes, pkt_count);
  debug_printf("DUT client index %u: Number of loopback packets = %u\n", client_num, loopback_pkt_count);

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
  wait_us(2000); // Since this task might be scheduled in a while(1), wait sometime before exiting so that xscope_control exits first in case of a shutdown command.
                 // Shutdown fails occasionally (To be debugged) otherwise.
}
