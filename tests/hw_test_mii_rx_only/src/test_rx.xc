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

#define NUM_TS_LOGS (42000)
void test_rx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 unsigned client_num)
{
  ethernet_macaddr_filter_t macaddr_filter;

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
  unsigned dut_timeout_s = 20; // dut timeout in seconds

  unsigned timestamps[NUM_TS_LOGS];
  unsigned counter = 0;

  while (!done)
  {
    select {
      case rx.packet_ready():
        unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
        ethernet_packet_info_t packet_info;
        rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);

        if (packet_info.type != ETH_DATA) {
          continue;
        }

        uint8_t dst_mac[MACADDR_NUM_BYTES], src_mac[MACADDR_NUM_BYTES];
        memcpy(dst_mac, rxbuf, MACADDR_NUM_BYTES);
        memcpy(src_mac, rxbuf+MACADDR_NUM_BYTES, MACADDR_NUM_BYTES);

        if(pkt_count == 0)
        {
          enable_time_based_check = 1;
          t :> time;
          test_end_time = time + (dut_timeout_s * XS1_TIMER_HZ);
        }
        if((pkt_count >= 0) && (pkt_count < 0 + NUM_TS_LOGS))
        {
          timestamps[counter++] = packet_info.timestamp;
        }


        pkt_count += 1;
        num_rx_bytes += packet_info.len;
        // swap src and dst mac addr
        /*memcpy(rxbuf, src_mac, MACADDR_NUM_BYTES);
        memcpy(rxbuf+MACADDR_NUM_BYTES, dst_mac, MACADDR_NUM_BYTES);

        tx.send_packet(rxbuf, packet_info.len, ETHERNET_ALL_INTERFACES);*/
        break;
#if ENABLE_DUT_TIMEOUT
      case (enable_time_based_check == 1) => t when timerafter(test_end_time) :> test_end_time:
        done = 1;
        break;
#endif
    } // select
  }


  unsigned print_pkt_count = (pkt_count > NUM_TS_LOGS) ? NUM_TS_LOGS : pkt_count;
  unsigned max_ifg = 0, min_ifg = 10000000; // Max and min observed IFG in reference

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
      if(diff > max_ifg)
      {
        max_ifg = diff;
      }
      else if(diff < min_ifg)
      {
        min_ifg = diff;
      }
      debug_printf("HP client: i=%d, ts_diff=%u, ts=(%u, %u)\n", i, (unsigned)diff, timestamps[i+1], timestamps[i] );
    }
  }
  debug_printf("counter = %u, min_ifg = %u, max_ifg = %u\n", counter, min_ifg, max_ifg);
  debug_printf("DUT: Received %d bytes, %d packets\n", num_rx_bytes, pkt_count);
}
