// Copyright 2013-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __mii_filter_h__
#define __mii_filter_h__
#include "ethernet.h"
#include "default_ethernet_conf.h"
#include "macaddr_filter.h"
#include "mii_buffering.h"

#ifdef __XC__

unsafe void mii_ethernet_filter(chanend c_conf,
                                packet_queue_info_t * unsafe incoming_packets,
                                packet_queue_info_t * unsafe rx_packets_lp,
                                packet_queue_info_t * unsafe rx_packets_hp);

#endif

#endif // __mii_filter_h__
