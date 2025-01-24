// Copyright 2013-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <debug_print.h>
#include <xclib.h>
#include <stdint.h>
#include <ethernet.h>
#include <otp_board_info.h>
#include <string.h>
#include <print.h>

void icmp_server(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 const unsigned char ip_address[4],
                 otp_ports_t &otp_ports)
{
  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < MACADDR_NUM_BYTES; i++)
    macaddr_filter.addr[i] = i;

  size_t index = rx.get_index();
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  // Add broadcast filter
  memset(macaddr_filter.addr, 0xff, MACADDR_NUM_BYTES);
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  cfg.add_ethertype_filter(index, 0x2222);

  debug_printf("Test started\n");
  unsigned pkt_count = 0;
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
      timestamps[pkt_count] = packet_info.timestamp;
      length[pkt_count] = packet_info.len;
      pkt_count += 1;
      if(pkt_count == 100)
      {
        done = 1;
      }
      if(pkt_count % 100 == 0)
      {
        printintln(pkt_count);
      }
      break;
    }
    if(done)
    {
      break;
    }
  }
  for(int i=0; i<99; i++)
  {
    debug_printf("i=%d, ts_diff=%u, len=%d,%d\n", i, (unsigned)(timestamps[i+1]-timestamps[i]), length[i], length[i+1] );
  }
}


