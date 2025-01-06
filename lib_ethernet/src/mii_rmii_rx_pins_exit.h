// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef __mii_rmii_exit_h__
#define __mii_rmii_exit_h__


// The size of the unsigned array for declaring locally as ISR context and stack
#define RXE_ISR_CONTEXT_WORDS       (3 + 2) // 3 args and 2 stack words

// These define the indicies into the ISR context array
#define RXE_ISR_STACK_OFFSET        3
#define RXE_PORT_OFFSET             2
#define RXE_CHANEND_OFFSET          1
#define RXE_SAVED_SP_OFFSET         0

/* ISR context structure
┌──────────────────────┐
│4 ISR stack 1         │
├──────────────────────┤
│3 ISR stack 0         │
├──────────────────────┤
│2 Port resource ID    │
├──────────────────────┤
│1 ISR trigger chanend │
├──────────────────────┤
│0 For saving user SP  │
└──────────────────────┘
*/


// These are tokens for tracking the ACK status from the ISR
#define RXE_ISR_ACK     0
#define RXE_RX_PINS_ACK 1


#ifdef __XC__

// The structure used for initialising the ISR
typedef struct rx_end_isr_ctx_t{
    int * unsafe isrstack;          // pointer to ISR context and stack array
    unsafe chanend c_rx_end;        // chanend of causing the ISR
    unsafe in buffered port:32 p;   // In port which we wish to unblock
}rx_end_isr_ctx_t;

// ASM utility for installing the ISR
void rx_end_install_isr(rx_end_isr_ctx_t *isr_ctx_p);

// Send signal to rx_end from other thread
void rx_end_send_sig(chanend c_rx_end);

// Used for synching at end of rx_pins
void rx_end_drain_and_clear(chanend c_rx_end);

// XC utility for uninstalling the ISR
static inline void rx_end_disable_interrupt(void){
    // TODO clear resource also?
    asm("clrsr 0x2");
}


#endif // __XC__

#endif // __mii_rmii_exit_h__