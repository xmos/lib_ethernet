// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

// This ISR installer and ISR allow another thread to "Break" from a block IN
// on a buffered port. It is used for exiting the Rx thread which would otherwise
// block if there was no network traffic


.cc_top rx_end_install_isr.func, rx_end_install_isr

#include <xs1.h>
#include "rmii_rx_pins_exit.h"


.globl rx_end_install_isr.nstackwords
.globl rx_end_install_isr.maxthreads
.globl rx_end_install_isr.maxtimers
.globl rx_end_install_isr.maxchanends
.globl rx_end_install_isr.maxsync
.type  rx_end_install_isr, @function
.linkset rx_end_install_isr.locnoside, 0
.linkset rx_end_install_isr.nstackwords, 0
.linkset rx_end_install_isr.maxchanends, 0
.linkset rx_end_install_isr.maxtimers, 0
.linkset rx_end_install_isr.maxthreads, 0
.linkset rx_end_install_isr.maxsync, 0


.globl rx_end_install_isr

// void rx_end_install_isr(isr_ctx_t *isr_ctx_p);
    .align 4
rx_end_install_isr:
    ENTSP_lu6 0                          // Force single issue mode, no stack needed

    ldap   r11, rx_end_isr_handler       // And set it up for interrupts.
    ldw    r1, r0[RXE_CHANEND_OFFSET]    // Get chanend ID
    setc   res[r1], XS1_SETC_IE_MODE_INTERRUPT
    setv   res[r1], r11
    eeu    res[r1]
  
    ldw    r2, r0[RXE_SAVED_SP_OFFSET]  // Get the address of the stack from the struct
                                        // This addr will get overwritten later by the kernel SP
    

    // Set up kernel stack.
    // This section sets up KSP (see xs3 arch guide - GETKSP) because we can't write directly
    ldaw   r11, sp[0]                   // Save SP into R11
    set    sp, r2                       // Set SP, and place old SP...
    stw    r11, sp[0]                   // ...where KRESTSP expects it
    krestsp 0                           // Set KSP, restore SP

    // Copy the chanend and port res IDs into the context for use in the ISR
    ldw    r3, r0[RXE_CHANEND_OFFSET]   // Get the chan ID
    stw    r3, r2[RXE_CHANEND_OFFSET]   // Save port ID in the ISR context
    ldw    r3, r0[RXE_PORT_OFFSET]      // Get the port ID
    stw    r3, r2[RXE_PORT_OFFSET]      // Save port ID in the ISR context

    setsr  XS1_SR_IEBLE_MASK            // Enable interrupts!
    retsp  0


    .align 4
rx_end_isr_handler:
    ENTSP_lu6 0 // Use single issue for simplicity
    kentsp 0    // Save user SP on kernel stack and set SP to kernel stack. Note we don't extend the SP

    // Push regs to pre-allocated ISR stack space 
    stw    r0, sp[RXE_ISR_STACK_OFFSET]
    stw    r11, sp[RXE_ISR_STACK_OFFSET + 1]

    // Consume the token that caused the interrupt
    // get    r11, ed // It's also in here but use ldw for clarity
    ldw    r11, sp[RXE_CHANEND_OFFSET]
    int    r0, res[r11]
    ldc    r0, RXE_ISR_ACK  // Send ACK with ISR ID
    outt   res[r11], r0

    // Unblock the port input by clearing conditions
    ldw    r0, sp[RXE_PORT_OFFSET]
    ldc    r11, 0x0 // No conditions, will fall straight through in select
    setd   res[r0], r11

rx_end_isr_exit:
    // Restore regs
    ldw    r0, sp[RXE_ISR_STACK_OFFSET]
    ldw    r11, sp[RXE_ISR_STACK_OFFSET + 1]
    krestsp 0   // Restore original stack pointer from kernel stack
    kret        // Return from interrupt

.cc_bottom rx_end_install_isr.func
