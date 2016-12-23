// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#include "ethernet.h"
#include "mii_filter.h"
#include "mii_buffering.h"
#include "print.h"
#include "macaddr_filter.h"
#include <stdint.h>
#include <xs1.h>
#include "ntoh.h"

#define DEBUG_UNIT ETHERNET_FILTER
#include "debug_print.h"


#ifndef ETHERNET_RX_CRC_ERROR_CHECK
#define ETHERNET_RX_CRC_ERROR_CHECK 1
#endif

#ifndef ETHERNET_MAC_PROMISCUOUS
#define ETHERNET_MAC_PROMISCUOUS 0
#endif

#ifndef ETHERNET_ENABLE_FILTER_TIMING
#define ETHERNET_ENABLE_FILTER_TIMING 0
#endif

#if ETHERNET_ENABLE_FILTER_TIMING
// Smallest packet + interframe gap is 84 bytes = 6.72 us
#pragma xta command "analyze endpoints rx_packet rx_packet"
#pragma xta command "set required - 6.72 us"
#endif

int mac_custom_filter_coerce(int);

static unsafe inline int is_broadcast(unsigned * unsafe buf)
{
  return (buf[0] & 0x1);
}

static unsafe inline int compare_mac(unsigned * unsafe buf,
                                     const unsigned mac[2])
{
  return ((buf[0] == mac[0]) && ((short) buf[1] == (short) mac[1]));
}

unsafe void mii_ethernet_filter(streaming chanend c,
                                chanend c_conf,
                                mii_packet_queue_t incoming_packets,
                                mii_packet_queue_t rx_packets_lp,
                                mii_packet_queue_t rx_packets_hp)
{
  eth_global_filter_info_t filter_info;
  ethernet_init_filter_table(filter_info);
  debug_printf("Starting filter\n");

  while (1) {
    select {
#pragma xta endpoint "rx_packet"
    case c_conf :> int:
      // Give the routing table to the ethernet server to reconfigure
      unsafe {
        eth_global_filter_info_t * unsafe  p = &filter_info;
        c_conf <: p;
        c_conf :> int;
      }
      break;

    default:
      break;
    }

    mii_packet_t * unsafe buf = mii_get_next_buf(incoming_packets);

    if (buf == null)
      continue;

    mii_move_rd_index(incoming_packets);

    unsigned length = buf->length; // Number of bytes in the frame minus the CRC
    unsigned crc;
    debug_printf("Filtering incoming packet (length %d)\n", buf->length);

    if (ETHERNET_RX_CRC_ERROR_CHECK)
      crc = buf->crc;

    debug_printf("Filter CRC result: %x\n", crc);

    if (length < 60 || (ETHERNET_RX_CRC_ERROR_CHECK && ~crc) || (length > ETHERNET_MAX_PACKET_SIZE)) {
      // Drop the packet
      continue;
    }

    int *unsafe p_len_type = (int *unsafe) &buf->data[3];
    uint16_t len_type = (uint16_t) NTOH_U16_ALIGNED(p_len_type);
    unsigned header_len = 14;
    if (len_type == 0x8100) {
      header_len += 4;
      p_len_type = (int *unsafe) &buf->data[4];
      len_type = (uint16_t) NTOH_U16_ALIGNED(p_len_type);
    }
    const unsigned rx_data_len = length - header_len;

    if ((len_type < 1536) && (len_type > rx_data_len)) {
      // Drop the packet
      continue;
    }

    buf->src_port = 0;
    buf->timestamp_id = 0;

    char * unsafe data = (char * unsafe) buf->data;
    int filter_result = ethernet_do_filtering(filter_info,
                                              (char *) buf->data,
                                              length,
                                              buf->filter_data);
    debug_printf("Filter result: %x\n", filter_result);
    buf->filter_result = filter_result;

    if (ethernet_filter_result_is_hp(filter_result)) {
      if (!mii_packet_queue_full(rx_packets_hp)) {
        mii_add_packet(rx_packets_hp, buf);
      } else {
        // Drop the packet because there is no room in the packet buffer
        // pointers
      }
    }
    else {
      if (!mii_packet_queue_full(rx_packets_lp)) {
        mii_add_packet(rx_packets_lp, buf);
      } else {
        // Drop the packet because there is no room in the packet buffer
        // pointers
      }
    }
  }
}
