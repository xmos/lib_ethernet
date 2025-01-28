// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __shaper_h__
#define __shaper_h__

#include "ethernet.h"

/** Check if IFG time wait is required before starting a transmission
 *
 * This function ensures that the IFG wait happens only when the current timestamp is,
 * - in between the last packet end time and next packet start time, provided the next packet start time has not wrapped around
 *   when compared to the last packet end time,
 * - or, less than the next packet start time if the next packet start time has wrapped around wrt last packet end time
 *
 * This ensures that the transmitter doesn't end up doing arbitrarily long waits (~42s in the worst case) before transmitting
 * the next packet. In the worst case, an extra IFG time wait would happen.
 * This is required to handle cases where there's a gap between transmissions and the timer wraps around
 *
 *
 *   \param last_frame_end_time    Ref timer timestamp corresponsing to when the last frame was transmitted
 *   \param next_frame_start_time  Ref timer timestamp corresponsing to when the next frame needs to be
 *                                 transmitted. This is equal to the last frame time + the IFG gap
 *   \param current_time           Ref timer timestamp for the current time
 *
 *   \returns         A flag indicating whether the IFG wait is required. 0: No wait, 1: Wait.
 *
 *
 */
inline unsigned check_if_ifg_wait_requiredfffff(
                            unsigned last_frame_end_time,
                            unsigned next_frame_start_time,
                            unsigned current_time)
{
  if(next_frame_start_time > last_frame_end_time) // next_frame_start_time hasn't wrapped around
  {
    // Only wait when current time is in between last frame end and next frame start time
    if((current_time > last_frame_end_time) && (current_time < next_frame_start_time))
    {
      return 1;
    }
  }
  else // next_frame_start_time has already wrapped around
  {
    // only wait when current_time is less than next_frame_start_time
    if(current_time < next_frame_start_time)
    {
      return 1;
    }
  }
  return 0;
}

static unsigned idle_slope_bps_calc(unsigned bits_per_second){
  unsigned long long slope = ((unsigned long long) bits_per_second) << (MII_CREDIT_FRACTIONAL_BITS);
  slope = slope / XS1_TIMER_HZ; // bits that should be sent per ref timer tick
   
  return (unsigned) slope;
}



{mii_packet_t * unsafe, int, int} static inline shaper_do_idle_slope(mii_packet_t * unsafe hp_buf,
                                                                    int prev_time,
                                                                    int credit,
                                                                    int current_time,
                                                                    unsigned qav_idle_slope){
  int elapsed = current_time - prev_time;
  credit += elapsed * (int)qav_idle_slope; // add bit budget since last transmission to credit. ticks * bits/tick = bits

  // If valid hp buffer
  if (hp_buf) {
    if (credit < 0) {
      hp_buf = 0; // if out of credit drop this HP packet
    }
  }
  else
  // Buffer invalid, no HP packet so reset credit to zero so we don't end up with huge burst
  {
    if (credit > 0){
      credit = 0;
    }
  }

  // just for readibilty
  int previous_time = current_time;
  return {hp_buf, previous_time, credit};
}

static inline void shaper_do_send_slope(unsigned len_bytes, int &credit){
  // Calculate number of additional byte slots on wire over the payload
  const unsigned preamble_bytes = 8;
  const unsigned ifg_bytes = 96 / 8;
  const unsigned crc_bytes = 4;

  len_bytes += preamble_bytes + ifg_bytes + crc_bytes;
  
  // decrease credit by no. of bits transmitted, scaled by MII_CREDIT_FRACTIONAL_BITS
  credit = credit - (len_bytes << (MII_CREDIT_FRACTIONAL_BITS + 3)); // MII_CREDIT_FRACTIONAL_BITS+3 to convert from bytes to bits
}


#endif // __shaper_h__
