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
{mii_packet_t * unsafe, int} static inline shaper_do_idle_slope(mii_packet_t * unsafe hp_buf,
                                                                int prev_time,
                                                                int credit,
                                                                int current_time,
                                                                unsigned qav_idle_slope){
return {hp_buf, previous_time, credit};

*/

int main()
{
    unsafe{
        mii_packet_t mii_packet;
        mii_packet_t * unsafe buff = &mii_packet;
        int result = 0;

        // GROUP1: last_frame_time is not wrapped around wrt next_frame_time
        int last_copy = 0;
        int credit = 0;
        unsigned qav_idle_slope = idle_slope_bps_calc(75000000); // Set to max reservation to test for overflows
        debug_printf("Idle_slope: %u\n", qav_idle_slope);
        int num_ticks_to_overflow = 0x7fffffff / qav_idle_slope;
        debug_printf("num_ticks_to_overflow: %d\n", num_ticks_to_overflow);


        // case 1: Small increment
        int last_frame_time = 0x00000000;
        int next_frame_time = 0x00001000;
        {buff, last_copy, credit} = shaper_do_idle_slope(buff, last_frame_time, credit, next_frame_time, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff != 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
            result = -1;
        }
        buff = &mii_packet;

        // case2: Small increment across halfway though
        credit = 0;
        last_frame_time = 0x7ffff800;
        next_frame_time = 0x80000800;
        {buff, last_copy, credit} = shaper_do_idle_slope(buff, last_frame_time, credit, next_frame_time, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff != 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
                result = -1;
        }
        buff = &mii_packet;

        // case3: Small increment over halfway though
        credit = 0;
        last_frame_time = 0x90000000;
        next_frame_time = 0x90001000;
        {buff, last_copy, credit} = shaper_do_idle_slope(buff, last_frame_time, credit, next_frame_time, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff != 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
                result = -1;
        }
        buff = &mii_packet;

        // case4: Reset and do big increment, will definitely overflow credit
        credit = 0;
        last_frame_time = 0x10000000;
        next_frame_time = 0x1000b000;
        {buff, last_copy, credit} = shaper_do_idle_slope(buff, last_frame_time, credit, next_frame_time, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff != 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
            result = -1;
        }
        buff = &mii_packet;

        // case5: Close to max
        credit = 0;
        last_frame_time = 0;
        next_frame_time = num_ticks_to_overflow - 10;
        {buff, last_copy, credit} = shaper_do_idle_slope(buff, last_frame_time, credit, next_frame_time, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff != 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
            result = -1;
        }
        buff = &mii_packet;

        // case6: Push case5 past overflow
        last_frame_time = 0;
        next_frame_time = 20;
        {buff, last_copy, credit} = shaper_do_idle_slope(buff, last_frame_time, credit, next_frame_time, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff != 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
            result = -1;
        }
        buff = &mii_packet;

        // GROUP2: next_frame_time has wrapped around wrt last_frame_time
        // case7: now is before next_frame_time
        credit = 0;
        last_frame_time = 0xfffff800;
        next_frame_time = 0x00000800;
        {buff, last_copy, credit} = shaper_do_idle_slope(buff, last_frame_time, credit, next_frame_time, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff != 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
            result = -1;
        }
        buff = &mii_packet;

        // case8: wrapping but REALLY big
        credit = 0;
        last_frame_time = 0xffffffff;
        next_frame_time = 0xfffffffe;
        {buff, last_copy, credit} = shaper_do_idle_slope(buff, last_frame_time, credit, next_frame_time, qav_idle_slope);
        if(!buff)
        {
            debug_printf("Error: Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", buff != 0 ? "True" : "False", last_frame_time, next_frame_time, credit);
            result = -1;
        }
        buff = &mii_packet;

        debug_printf("%s\n", result == 0 ? "PASS" : "FAIL");
        return result;
    }
}
