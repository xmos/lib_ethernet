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

int test_num = 1;

int do_test(int last_time, int current_time, qav_state_t *qav_state, ethernet_port_state_t *port_state){
    unsafe{
        int result = 0;
        int t0;
        int t1;
        timer tmr;

        mii_packet_t mii_packet;
        mii_packet_t * unsafe buff = &mii_packet;

        qav_state->prev_time = last_time;
        qav_state->current_time = current_time;
        tmr :> t0;
        buff = shaper_do_idle_slope(buff, qav_state, port_state);
        tmr :> t1;
        debug_printf("Ticks: %d\n", t1-t0);
        if(!buff)
        {
            debug_printf("Error test (%d): Unexpected buff %s, last_end_time 0x%8x, next_start_time 0x%8x, credit: %d\n", test_num, buff != 0 ? "True" : "False", last_time, qav_state->current_time, qav_state->credit);
            result = -1;
        }
        
        test_num++;
        return result;
    }
}

// For dev only not main test. This is to observe the shaper behaviour
void do_characterise(void){unsafe{
    ethernet_port_state_t port_state = {0};
    qav_state_t qav_state = {0, 0, 0};
    set_qav_idle_slope(&port_state, 75000000); // Set to max reservation to test for overflows
    // set_qav_credit_limit(&port_state, ETHERNET_MAX_PACKET_SIZE);
    set_qav_credit_limit(&port_state, 0);

    mii_packet_t mii_packet;
    mii_packet_t * unsafe buff = &mii_packet;

    qav_state.prev_time = 0;
    qav_state.current_time = 0;
    debug_printf("credit: %d\n", qav_state.credit);

    int time_inc = 20 * 8;

    for(int i = 0; i < 20; i++){
        int ishp = ((i % 3) == 0);
        if(ishp) buff = &mii_packet; else buff = 0;
        qav_state.current_time += 10;
        buff = shaper_do_idle_slope(buff, &qav_state, &port_state);
        debug_printf("%d %s credit: %d - ", i, ishp == 0 ? "LP":"HP", qav_state.credit);
        debug_printf("HP Tx: %s\n", buff != 0 ? "True" : "False");
        
        if(ishp && buff){
            debug_printf("do send slope\n");
            shaper_do_send_slope(40, &qav_state);
        }
        qav_state.current_time += time_inc;

        if(i == 10) time_inc = 40 * 8;
    }
}}

// To make volatile
in port p_vol = XS1_PORT_1A;

int main(void){
    // do_characterise();

    unsafe{
        ethernet_port_state_t port_state;
        qav_state_t qav_state = {0, 0, 0};

        int result = 0;

        int vol, vol2;
        p_vol :> vol; // This will be zero. We add these to force the compiler to call shaper_do_idle_slope fpor the timing analysis
        p_vol :> vol2;// otherwise the const expressions get optimised away

        // GROUP1: last_frame_time is not wrapped around wrt next_frame_time
        int last_copy = 0;

        port_state.link_speed = LINK_100_MBPS_FULL_DUPLEX;
        set_qav_idle_slope(&port_state, 75000000); // Set to max reservation to test for overflows
        set_qav_credit_limit(&port_state, ETHERNET_MAX_PACKET_SIZE);

        debug_printf("Idle_slope: %u\n", port_state.qav_idle_slope);
        debug_printf("credit_limit: %d\n", port_state.qav_credit_limit);

        // case 1: Small increment
        result -= do_test(0x00000000 + vol, 0x00000100 + vol2, &qav_state, &port_state);
     

        // case2: Small increment across halfway though
        qav_state.credit = 0;
        result -= do_test(0x7ffff800 + vol, 0x80000800 + vol2, &qav_state, &port_state);

        // case3: Small increment over halfway though
        qav_state.credit = 0;
        result -= do_test(0x90000000 + vol, 0x90001000 + vol2, &qav_state, &port_state);

        // case4: Reset and do big increment, will definitely overflow credit
        qav_state.credit = 0;
        result -= do_test(0x00000000 + vol, 0x90000000  + vol2, &qav_state, &port_state);
     
        // case5: Close to max
        qav_state.credit = 0;
        result -= do_test(0 + vol, 0x7fffffff + vol2, &qav_state, &port_state);

        // case6: Push case5 past overflow
        result -= do_test(0 + vol, 20 + vol2, &qav_state, &port_state);

        // GROUP2: next_frame_time has wrapped around wrt last_frame_time
        // case7: now is before next_frame_time
        qav_state.credit = 0;
        result -= do_test(0xfffff800 + vol, 0x00000800 + vol2, &qav_state, &port_state);
      
        // case8: wrapping but REALLY big
        qav_state.credit = 0;
        result -= do_test(0xffffffff + vol, 0xfffffffe + vol2, &qav_state, &port_state);

        debug_printf("%s\n", result == 0 ? "PASS" : "FAIL");
        return result;
    }
}
