// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <print.h>
#include "rmii_rx_pins_exit.h"

static void drain_tokens(chanend c){
    char token;
    while(1){
        select{
            case inuchar_byref(c, token):
                // consume token
                break;
            default:
                // Nothing left
                return;
                break;
            }
    }
}

/* 
The way this works is the following:

The MAC server sends a data token to rx_pins. This causes an ISR. In the ISR we send an ACK token back.
If the token is identified as RXE_ISR_ACK then we know it hasn't exited yet, so continue looping.
If the token is RXE_RX_PINS_ACK we know that rx_pins has exited. 
Then we drain any excess tokens and both sides send a XS1_CT_END control token (and consume) to ensure
that the channel has been closed before we exit so all is left clean.

The whole scheme aims to avoid any potential channel filling/blocking by always sending an ACK rather
than a blind exit data token being sent many times which may block the server. The drains may not be
needed but are included just in case there are any weird race conditions, which can happen with ISRs.
*/

void rx_end_send_sig(chanend c_rx_pins_exit){
    while(1){
        outuchar(c_rx_pins_exit, 0); // Send endin via ISR
        // printintln(i);
        delay_microseconds(1);       // Allow next IN to be hit (set to 100 bit times - max 32 bit times for mii or 16 for rmii between INs)
                                     // Without this we would always be in the ISR

        // Receive ACK
        char token = inuchar(c_rx_pins_exit);
        if(token == RXE_RX_PINS_ACK){
            break;
        }

    }
    drain_tokens(c_rx_pins_exit);
    outct(c_rx_pins_exit, XS1_CT_END);  // Clear channel in this direction (to rx_pins)
    inct(c_rx_pins_exit);               // Consume clear from rx_pins
}


void rx_end_drain_and_clear(chanend c_rx_pins_exit){
    outuchar(c_rx_pins_exit, RXE_RX_PINS_ACK); // Send ACK

    // Now drain channel of data tokens until we hit a control token
    int next_token_is_ct = 0;
    while(!next_token_is_ct){
        next_token_is_ct = testct(c_rx_pins_exit);
        if(!next_token_is_ct){
            // consume data token
            inuchar(c_rx_pins_exit);
        }
    }

    inct(c_rx_pins_exit);              // Consume control token from clear channel at rx_pins
    outct(c_rx_pins_exit, XS1_CT_END); // Clear channel in other directon
}