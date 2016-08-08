// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#ifndef __default_ethernet_conf_h__
#define __default_ethernet_conf_h__

#ifdef __ethernet_conf_h_exists__
#include "ethernet_conf.h"
#endif

#ifndef ETHERNET_SUPPORT_HP_QUEUES
#define ETHERNET_SUPPORT_HP_QUEUES (0)
#endif

#ifndef ETHERNET_SUPPORT_TRAFFIC_SHAPER
#define ETHERNET_SUPPORT_TRAFFIC_SHAPER (0)
#endif

#ifndef ETHERNET_FILTER_SPECIALIZATION
  #define ETHERNET_FILTER_SPECIALIZATION
  #ifndef ETHERNET_ENABLE_FILTER_TIMING
  #define ETHERNET_ENABLE_FILTER_TIMING 0
  #endif
#else
  #ifndef ETHERNET_ENABLE_FILTER_TIMING
  #define ETHERNET_ENABLE_FILTER_TIMING 1
  #endif
#endif

#ifndef ETHERNET_RX_CLIENT_QUEUE_SIZE
  #if RGMII
    #define ETHERNET_RX_CLIENT_QUEUE_SIZE (16)
  #else
    #define ETHERNET_RX_CLIENT_QUEUE_SIZE (4)
  #endif
#endif

#ifndef ETHERNET_TX_MAX_PACKET_SIZE
#define ETHERNET_TX_MAX_PACKET_SIZE ETHERNET_MAX_PACKET_SIZE
#endif

#ifndef ETHERNET_RX_MAX_PACKET_SIZE
#define ETHERNET_RX_MAX_PACKET_SIZE ETHERNET_MAX_PACKET_SIZE
#endif

#ifndef RGMII_MAC_BUFFER_COUNT
// Provide enough buffers to receive all minumum sized frames after
// a maximum sized frame
// Keep these as a power of 2 for performance reasons
#define RGMII_MAC_BUFFER_COUNT_RX 32
#define RGMII_MAC_BUFFER_COUNT_TX 8
#endif

#ifndef ETHERNET_USE_HARDWARE_LOCKS
#define ETHERNET_USE_HARDWARE_LOCKS 1
#endif

#ifndef ETHERNET_NUM_PACKET_POINTERS
// Keep this as a power of 2 for performance reasons
#define ETHERNET_NUM_PACKET_POINTERS 32
#endif

#ifndef MII_MACADDR_HASH_TABLE_SIZE
#define MII_MACADDR_HASH_TABLE_SIZE 256
#endif

#ifndef MII_TIMESTAMP_QUEUE_MAX_SIZE
#define MII_TIMESTAMP_QUEUE_MAX_SIZE 10
#endif

#ifndef ETHERNET_MAX_ETHERTYPE_FILTERS
#define ETHERNET_MAX_ETHERTYPE_FILTERS 2
#endif

#ifndef __SIMULATOR__
#define __SIMULATOR__ 0
#endif

#endif // __default_ethernet_conf_h__