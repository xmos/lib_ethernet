// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
.cc_top mii_lite_install_handler.func, mii_lite_install_handler

#include <xs1.h>

#define EEBLE XS1_SR_EEBLE_MASK
#define IEBLE XS1_SR_IEBLE_MASK

#define KERNEL_STACK_SAVE 12         // TODO: make smaller

// call: int mii_lite_install_handler(chanend interrupt, int buffer[])
.globl mii_lite_install_handler.nstackwords
.globl mii_lite_install_handler.maxthreads
.globl mii_lite_install_handler.maxtimers
.globl mii_lite_install_handler.maxchanends
.globl mii_lite_install_handler.maxsync
.type  mii_lite_install_handler, @function
.linkset mii_lite_install_handler.locnoside, 0
.linkset mii_lite_install_handler.nstackwords, 0
.linkset mii_lite_install_handler.maxchanends, 0
.linkset mii_lite_install_handler.maxtimers, 0
.linkset mii_lite_install_handler.maxthreads, 0
.linkset mii_lite_install_handler.maxsync, 0

.globl mii_lite_install_handler

#define next_buffer                 0
#define packet_in_lld               1
#define notification_channel_end    2
#define mii_channel_end             3
#define mii_packets_overran         4
#define kernel_stack_end            148


    .align 4
mii_lite_install_handler:
    ENTSP_lu6 0                              //    force single issue mode
    setd   res[r3], r3                       //    synchronising interrupt routine and user land
    stw    r3, r0[notification_channel_end]  //    it points to itself

    stw    r2, r0[mii_channel_end]       // Step 2: Channel end to MIILLD layer, store it
    ldap   r11, mii_interrupt_handler    //         and set it up for interrupts.
    setc   res[r2], XS1_SETC_IE_MODE_INTERRUPT
    setv   res[r2], r11
    eeu    res[r2]
    mov    r11, r0
    setev  res[r2], r11                // Step 3: Set the EV to the mii_lite_data_t structure so that
                                       //         the ED will contain the pointer on interrupt

    ldc    r3, kernel_stack_end
    ldaw   r2, r0[r3]                  // Step 5: Set up kernel stack.
    ldaw   r11, sp[0]                  //         Save SP into R11
    set    sp, r2                      //         Set SP, and place old SP...
    stw    r11, sp[0]                  //         ...where KRESTSP expects it
    krestsp 0                          //         Set KSP, restore SP

    ldw    r2, r0[mii_channel_end]     // Step 6: provide LLD with first buffer
    out    res[r2], r1
    stw    r1, r0[packet_in_lld]       //         packet_in_lld holds pointer passed to LLD.

    setsr  IEBLE                       // Step 7: Enable interrupts!
    retsp  0


    .align 4
mii_interrupt_handler:
    ENTSP_lu6 0
    kentsp KERNEL_STACK_SAVE
    stw    r3, sp[4]
    stw    r2, sp[3]
    stw    r11, sp[5]

    get    r11, ed
    ldw    r3, r11[mii_channel_end]
    in     r2, res[r3]               // Watch out: the number of instructions between interrupt and out should be
                                     // no less than 10, no more than 40.
    stw    r1, sp[2]

    ldc    r1, 0
    out    res[r3], r1

    stw    r0, sp[1]
    stw    lr, sp[6]
    mov    r0, r11
    nop
    nop
    nop
    nop
    nop

    ldw    r1, r0[packet_in_lld]
    ldw    r11, r0[next_buffer]

    add    r11, r11, 1
    bt     r11, buffers_available
    out    res[r3], r1               // Reuse this buffer - drop current packet.
    ldw    r3, r0[mii_packets_overran]
    add    r3, r3, 1
    stw    r3, r0[mii_packets_overran]
    bu     return_from_interrupt
buffers_available:
    sub    r11, r11, 1
    out    res[r3], r11               // Pass fresh buffer.
    stw    r11, r0[packet_in_lld]
    ldw    r3, r0[notification_channel_end]
    // r0: struct
    // r1: base
    // r2: end
    // r3: notification_channel_end
    bl     mii_client_user

return_from_interrupt:

    ldw    r0, sp[1]
    ldw    r1, sp[2]
    ldw    r2, sp[3]
    ldw    r3, sp[4]
    ldw    r11, sp[5]
    ldw    lr, sp[6]
    krestsp KERNEL_STACK_SAVE

    kret

.cc_bottom mii_lite_install_handler.func
