#include "xs1.h"

.section .dp.data, "awd", @progbits

// The byte-reversed version of the tag
.align 4
.globl mii_per_core_error
mii_per_core_error:
.word 0,0,0,0,0,0,0,0

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
        entsp 0

        setc res[r0], XS1_SETC_IE_MODE_INTERRUPT
        ldc r1, 1
        setd res[r0], r1
        setc res[r0], XS1_SETC_COND_EQ

        ldap r11, mii_error_interrupt_handler
        setv res[r0], r11
        eeu res[r0]

        // Return the address that the error will be stored in
        get r11, id
        ldaw r0, dp[mii_per_core_error]
        ldaw r0, r0[r11]

        retsp 0

mii_error_interrupt_handler:
        extsp 2
        stw r0, sp[0]
        stw r11, sp[1]

        // Clear the interrupt
        get r11, ed
        in r0, res[r11]
        setc res[r11], XS1_SETC_COND_EQ

        // Signal the error through the shared pointer
        get r11, id
        ldaw r0, dp[mii_per_core_error]
        ldaw r0, r0[r11]
        stw r0, r0[0]

        ldw r11, sp[1]
        ldw r0, sp[0]

        ldaw sp, sp[2]
        kret
        
        .align 4
        .cc_bottom mii_setup_error_port.function

