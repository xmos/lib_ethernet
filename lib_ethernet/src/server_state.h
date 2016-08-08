// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#ifndef __server_state_h__
#define __server_state_h__

#include "xccompat.h"
#include "ethernet.h"

#define MII_CREDIT_FRACTIONAL_BITS 16

// Data structure to keep track of server MAC port data
typedef struct ethernet_port_state_t
{
  ethernet_link_state_t link_state;
  ethernet_speed_t link_speed;
  int qav_shaper_enabled;
  int qav_idle_slope;
  int ingress_ts_latency[NUM_ETHERNET_SPEEDS];
  int egress_ts_latency[NUM_ETHERNET_SPEEDS];
} ethernet_port_state_t;

void init_server_port_state(REFERENCE_PARAM(ethernet_port_state_t, state), int enable_qav_shaper);

#endif // __server_state_h__
