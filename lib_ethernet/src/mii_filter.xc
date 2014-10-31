// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>
#include "ethernet.h"
#include "mii_filter.h"
#include "mii_buffering.h"
#include "print.h"
#include <xs1.h>

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

unsafe void mii_ethernet_filter(const char mac_address[6], streaming chanend c,
                                client ETHERNET_FILTER_SPECIALIZATION ethernet_filter_callback_if i_filter)
{
  unsigned int mac[2];
  mii_packet_t * unsafe buf;
  // create integer version of mac address for speed
  mac[0] = mac_address[0] + (((unsigned) mac_address[1]) << 8)+ (((unsigned) mac_address[2]) << 16)  + (((unsigned) mac_address[3]) << 24);
  mac[1] = (((unsigned) mac_address[4])) + (((unsigned) mac_address[5]) << 8);

  debug_printf("Starting filter\n");
  while (1) {
    select {
#pragma xta endpoint "rx_packet"
    case c :> buf :
      if (buf) {
        unsigned length = buf->length;
        unsigned crc;
        debug_printf("Filtering incoming packet (length %d)\n", buf->length);

        if (ETHERNET_RX_CRC_ERROR_CHECK)
          crc = buf->crc;

        debug_printf("Filter CRC result: %x\n", crc);

        buf->src_port = 0;
        buf->timestamp_id = 0;

        if (length < 60 || (ETHERNET_RX_CRC_ERROR_CHECK && ~crc)) {
          buf->filter_result = 0;
          buf->stage = 1;
        } else  {
          int broadcast = is_broadcast(buf->data);
          int unicast = compare_mac(buf->data, mac);
          if (ETHERNET_MAC_PROMISCUOUS || broadcast || unicast) {
            debug_printf("Initial filter passed\n");
            char * unsafe data = (char * unsafe) buf->data;
            int filter_result = 0, filter_data = 0;
            {filter_result, filter_data} = i_filter.do_filter((char *) data,
                                                              buf->length);
            debug_printf("User filter result: %x\n", filter_result);
            #if 0
            if (!unicast && ENABLE_ETHERNET_PORT_FORWARDING) {
              filter_result |= ETHERNET_FILTER_PORT_FORWARD_MASK;
            }
            #endif
            buf->filter_result = filter_result;
            buf->filter_data = filter_data;
            buf->stage = 1;
          }
        }
      } // end if (buf)
      break;
    } // end select
  } // end while (1)
}
