// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __server_state_h__
#define __server_state_h__

#include "xccompat.h"
#include "ethernet.h"

// Server is shared for rmii/mii so pass in enum
typedef enum phy_100mb_t {
    ETH_MAC_IF_MII = 0,
    ETH_MAC_IF_RMII
} phy_100mb_t;

// Data structure to keep track of server MAC port data
typedef struct ethernet_port_state_t
{
  ethernet_link_state_t link_state;
  ethernet_speed_t link_speed;
  int qav_shaper_enabled;
  int qav_idle_slope;
  int64_t qav_credit_limit;
  int ingress_ts_latency[NUM_ETHERNET_SPEEDS];
  int egress_ts_latency[NUM_ETHERNET_SPEEDS];
} ethernet_port_state_t;

void init_server_port_state(REFERENCE_PARAM(ethernet_port_state_t, state), int enable_qav_shaper);

#endif // __server_state_h__
