// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include "xs1.h"
#include "mii_buffering_defines.h"

.section .dp.data, "awd", @progbits

// The byte-reversed version of the tag
.cc_top mii_common.data
.align 4
.globl mii_per_core_error
mii_per_core_error_and_dv:
.word 0,0,0,0,0,0,0,0
.word 0,0,0,0,0,0,0,0
.cc_bottom mii_common.data

.text
        .cc_top mii_setup_error_port.function
        .set    mii_setup_error_port.nstackwords,0
        .globl  mii_setup_error_port.nstackwords
        .set    mii_setup_error_port.maxcores,1
        .globl  mii_setup_error_port.maxcores
        .set    mii_setup_error_port.maxtimers,0
        .globl  mii_setup_error_port.maxtimers
        .set    mii_setup_error_port.maxchanends,0
        .globl  mii_setup_error_port.maxchanends

        .globl  mii_setup_error_port
        .align  4
        .type   mii_setup_error_port,@function
#if defined(__XS2A__)
        .issue_mode single
#endif
mii_setup_error_port:
        ENTSP_lu6 0

        ldc    r3, MII_COMMON_HANDLER_STACK_WORDS - 1
        ldaw   r3, r2[r3]                  // Set up kernel stack.
        ldaw   r11, sp[0]                  // Save SP into R11
        set    sp, r3                      // Set SP, and place old SP...
        stw    r11, sp[0]                  // ...where KRESTSP expects it
        krestsp 0                          // Set KSP, restore SP

        setc res[r0], XS1_SETC_IE_MODE_INTERRUPT
        ldc r2, 1
        setd res[r0], r2
        setc res[r0], XS1_SETC_COND_EQ

        ldap r11, mii_error_interrupt_handler
        setv res[r0], r11
        eeu res[r0]

        // Return the address that the error will be stored in
        get r11, id

        ldaw r0, dp[mii_per_core_error_and_dv]
        ldaw r0, r0[r11]

        // Store off the DV port ID
        stw r1, r0[8]

        retsp 0

mii_error_interrupt_handler:
        ENTSP_lu6 0
        kentsp MII_COMMON_HANDLER_STACK_WORDS - 1
        stw r0, sp[0]
        stw r11, sp[1]

        // Compute address of data in memory
        get r11, id
        ldaw r0, dp[mii_per_core_error_and_dv]
        ldaw r0, r0[r11]

        // Signal the error through the shared pointer
        stw r0, r0[0]

mii_error_interrupt_handler_ignore:
        // Clear the interrupt
        get r11, ed
        in r0, res[r11]
        setc res[r11], XS1_SETC_COND_EQ


        ldw r11, sp[1]
        ldw r0, sp[0]

        krestsp MII_COMMON_HANDLER_STACK_WORDS - 1
        kret
        
        .align 4
        .cc_bottom mii_setup_error_port.function

