// Copyright 2013-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __mii_filter_h__
#define __mii_filter_h__
#include "ethernet.h"
#include "default_ethernet_conf.h"
#include "macaddr_filter.h"
#include "mii_buffering.h"

#ifdef __XC__

unsafe void mii_ethernet_filter(chanend c_conf,
                                mii_packet_queue_t incoming_packets,
                                mii_packet_queue_t rx_packets_lp,
                                mii_packet_queue_t rx_packets_hp,
                                volatile int * unsafe running_flag_ptr);

#endif

#endif // __mii_filter_h__
