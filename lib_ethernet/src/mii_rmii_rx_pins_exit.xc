// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <print.h>
#include "mii_rmii_rx_pins_exit.h"

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