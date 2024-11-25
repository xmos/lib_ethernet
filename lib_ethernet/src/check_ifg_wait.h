#ifndef __check_ifg_wait_h__
#define __check_ifg_wait_h__


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
inline unsigned check_if_ifg_wait_required(
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

#endif
