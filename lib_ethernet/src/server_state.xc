// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include "server_state.h"
#include "string.h"

void init_server_port_state(ethernet_port_state_t &state, int enable_qav_shaper)
{
  memset(&state, 0, sizeof(ethernet_port_state_t));
  state.link_state = ETHERNET_LINK_DOWN;
  state.qav_shaper_enabled = enable_qav_shaper;
  state.qav_idle_slope = (11<<MII_CREDIT_FRACTIONAL_BITS);
}
