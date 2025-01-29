// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include "ethernet.h"
#include "shaper.h"

void set_qav_idle_slope(ethernet_port_state_t * port_state, unsigned limit_bps)
{
  // Scale for 16.16 representation 
  uint64_t slope = ((uint64_t)limit_bps) << MII_CREDIT_FRACTIONAL_BITS;

  // Calculate bits per tick per bit in 16.16
  slope = slope / XS1_TIMER_HZ;
  
  port_state->qav_idle_slope = (unsigned)slope;
}


void set_qav_credit_limit(ethernet_port_state_t * port_state, int payload_limit_bytes)
{
  int64_t max_interferring_frame_bits = (preamble_bytes + payload_limit_bytes + crc_bytes + ifg_bytes) * 8;
  port_state->qav_credit_limit = max_interferring_frame_bits;
}
