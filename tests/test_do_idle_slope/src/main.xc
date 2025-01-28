// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <platform.h>
#include <print.h>
#include "debug_print.h"
#include <xassert.h>
#include "ethernet.h"
#include "mii_buffering.h"
#include "shaper.h"

/*
inline mii_packet_t * unsafe shaper_do_idle_slope(mii_packet_t * unsafe buf,
                                                  int curr_time,
                                                  int &prev_time,
                                                  int &credit,
                                                  unsigned qav_idle_slope
*/

int main()
{
    unsafe{
        mii_packet_t mii_packet;
        mii_packet_t * unsafe buff = &mii_packet;
        int result = 0;

        // GROUP1: last_frame_time is not wrapped around wrt next_frame_time
        int last_frame_time = 0xe0000000;
        int next_frame_time = 0xf0000000;
        int credit = 0;
        unsigned qav_idle_slope = idle_slope_bps_calc(75000000); // Set to max reservation to test for overflows

        // case 1: now is somewhere between last and next
        buff = shaper_do_idle_slope(buff, last_frame_time, next_frame_time, credit, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff == 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
            result = -1;
        }
        buff = &mii_packet;

        // case2: now is outside the window and more than next_frame_time
        buff = shaper_do_idle_slope(buff, last_frame_time, next_frame_time, credit, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff == 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
                result = -1;
        }
        buff = &mii_packet;

        // case3: now is outside the window and wrapped around
        buff = shaper_do_idle_slope(buff, last_frame_time, next_frame_time, credit, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff == 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
            result = -1;
        }
        buff = &mii_packet;

        // GROUP2: next_frame_time has wrapped around wrt last_frame_time
        last_frame_time = 0xffff0000;
        next_frame_time = 0x10000000;

        // case4: now is before next_frame_time
        buff = shaper_do_idle_slope(buff, last_frame_time, next_frame_time, credit, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff == 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
            result = -1;
        }
        buff = &mii_packet;

        // case5: now is after next_frame_time
        buff = shaper_do_idle_slope(buff, last_frame_time, next_frame_time, credit, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff == 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
            result = -1;
        }
        buff = &mii_packet;

        debug_printf("%s\n", result == 0 ? "PASS" : "FAIL");
        return result;
    }
}
