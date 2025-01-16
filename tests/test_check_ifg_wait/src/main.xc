// Copyright 2024-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <platform.h>
#include <print.h>
#include "debug_print.h"
#include "check_ifg_wait.h"
#include <xassert.h>

int main()
{
    // GROUP1: next_frame_start_time is not wrapped around wrt last_frame_end_time
    unsigned last_frame_end_time = 0xe0000000;
    unsigned next_frame_start_time = 0xf0000000;

    // case 1: now is somewhere between last and next
    unsigned now = 0xeeeeffff;
    unsigned wait = check_if_ifg_wait_required(last_frame_end_time, next_frame_start_time, now);
    if(!wait)
    {
        debug_printf("Error: Unexpected wait %d, last_end_time 0x%8x, next_start_time 0x%8x, now 0x%8x\n", wait, last_frame_end_time, next_frame_start_time, now);
    }

    // case2: now is outside the window and more than next_frame_start_time
    now = 0xffffffff;
    wait = check_if_ifg_wait_required(last_frame_end_time, next_frame_start_time, now);
    if(wait)
    {
        debug_printf("Error: Unexpected wait %d, last_end_time 0x%8x, next_start_time 0x%8x, now 0x%8x\n", wait, last_frame_end_time, next_frame_start_time, now);
    }

    // case3: now is outside the window and wrapped around
    now = 0x10000000;
    wait = check_if_ifg_wait_required(last_frame_end_time, next_frame_start_time, now);
    if(wait)
    {
        debug_printf("Error: Unexpected wait %d, last_end_time 0x%8x, next_start_time 0x%8x, now 0x%8x\n", wait, last_frame_end_time, next_frame_start_time, now);
    }

    // GROUP2: next_frame_start_time has wrapped around wrt last_frame_end_time
    last_frame_end_time = 0xffff0000;
    next_frame_start_time = 0x10000000;

    // case4: now is before next_frame_start_time
    now = 0x01000000;
    wait = check_if_ifg_wait_required(last_frame_end_time, next_frame_start_time, now);
    if(!wait)
    {
        debug_printf("Error: Unexpected wait %d, last_end_time 0x%8x, next_start_time 0x%8x, now 0x%8x\n", wait, last_frame_end_time, next_frame_start_time, now);
    }

    // case5: now is after next_frame_start_time
    now = 0xff000000;
    wait = check_if_ifg_wait_required(last_frame_end_time, next_frame_start_time, now);
    if(wait)
    {
        debug_printf("Error: Unexpected wait %d, last_end_time 0x%8x, next_start_time 0x%8x, now 0x%8x\n", wait, last_frame_end_time, next_frame_start_time, now);
    }
    debug_printf("PASS\n");
    return 0;
}
