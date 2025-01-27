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


void test_rx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 chanend c_shutdown,
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
  unsigned timestamps[100];
  unsigned length[100];
  unsigned done = 0;
  while (1)
  {
    select {
      case rx.packet_ready():
        unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
        unsigned char txbuf[ETHERNET_MAX_PACKET_SIZE];
        ethernet_packet_info_t packet_info;
        rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);

        if (packet_info.type != ETH_DATA)
          continue;

        // Random data packet
        //printintln(9999);
        num_rx_bytes += packet_info.len;
        if(pkt_count < 100)
        {
          timestamps[pkt_count] = packet_info.timestamp;
          length[pkt_count] = packet_info.len;
          /*if(pkt_count == 100)
          {
            done = 1;
          }
          if(pkt_count % 100 == 0)
          {
            printintln(pkt_count);
          }*/
        }
        pkt_count += 1;
        break;

      case c_shutdown :> int done:
        debug_printf("lp client %d, Received %d lp bytes, %d lp packets\n", client_num, num_rx_bytes, pkt_count);
        c_shutdown <: 1;
        done = 1;
        break;
    } // select

    if(done)
    {
      break;
    }
  }
  for(int i=0; i<pkt_count; i++)
  {
    debug_printf("i=%d, ts_diff=%u, len=%d,%d\n", i, (unsigned)(timestamps[i+1]-timestamps[i]), length[i], length[i+1] );
  }
}


void test_rx_hp(client ethernet_cfg_if cfg,
                streaming chanend c_rx_hp,
                chanend c_shutdown[num_lp_clients],
                unsigned num_lp_clients
               )
{
  set_core_fast_mode_on();

  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i + num_lp_clients;
  cfg.add_macaddr_filter(0, 1, macaddr_filter);

  unsigned pkt_count = 0;
  unsigned num_rx_bytes = 0;
  unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
  timer t;
  unsigned time;
  t :> time;
  unsigned test_end_time;
  unsigned enable_time_based_check = 0;
  unsigned done = 0;
  unsigned timestamps[100];
  unsigned length[100];

  while (!done) {
    ethernet_packet_info_t packet_info;

    #pragma ordered
    select {
      case ethernet_receive_hp_packet(c_rx_hp, rxbuf, packet_info):
        // Check the first byte after the header (which can be VLAN tagged)
        num_rx_bytes += packet_info.len;
        if(pkt_count < 100)
        {
          timestamps[pkt_count] = packet_info.timestamp;
          length[pkt_count] = packet_info.len;
        }
        pkt_count += 1;
        if(pkt_count == 1)
        {
          enable_time_based_check = 1;
          // Test ends 10 seconds after the 1st packet is received.
          t :> time;
          test_end_time = time + (10 * XS1_TIMER_HZ);
        }
        break;

      case (enable_time_based_check == 1) => t when timerafter(test_end_time) :> test_end_time:
        done = 1;
        break;
    }
  }
  debug_printf("Received %d hp bytes, %d hp packets\n", num_rx_bytes, pkt_count);
  unsigned print_pkt_count = (pkt_count > 100) ? 100 : pkt_count;

  for(int i=0; i<print_pkt_count-1; i++)
  {
    debug_printf("i=%d, ts_diff=%u, len=%d,%d\n", i, (unsigned)(timestamps[i+1]-timestamps[i]), length[i], length[i+1] );
  }
  for(int i=0; i<num_lp_clients; i++)
  {
    c_shutdown[i] <: 1;
    c_shutdown[i] :> int temp;
  }
  exit(0);
}

