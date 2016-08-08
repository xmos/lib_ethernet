// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#ifndef __mii_filter_h__
#define __mii_filter_h__
#include "ethernet.h"
#include "default_ethernet_conf.h"
#include "macaddr_filter.h"
#include "mii_buffering.h"

#ifdef __XC__

unsafe void mii_ethernet_filter(streaming chanend c,
                                chanend c_conf,
                                mii_packet_queue_t incoming_packets,
                                mii_packet_queue_t rx_packets_lp,
                                mii_packet_queue_t rx_packets_hp);

#endif

#endif // __mii_filter_h__
