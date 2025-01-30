// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include "server_state.h"
#include "string.h"

void init_server_port_state(ethernet_port_state_t &state, int enable_qav_shaper)
{
  memset(&state, 0, sizeof(ethernet_port_state_t));
  state.link_state = ETHERNET_LINK_DOWN;
  state.qav_shaper_enabled = enable_qav_shaper;
  state.qav_credit_limit = 0; // No credit limit
  state.qav_idle_slope = (11<<MII_CREDIT_FRACTIONAL_BITS); // 11 bits per tick (more than max egress even in gbit)
}
