// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>


    .section .cp.rodata,     "ac", @progbits
    .align 4
.cc_top rmiiconsts.data
    .globl polynomial

initial_crc:
    .word 0x9226F562
all_fives:
    .word 0x55555555
Dall_fives:
    .word 0xD5555555
.cc_bottom rmiiconsts.data



.cc_top master_4x_pins_4b_body_asm.func, master_4x_pins_4b_body_asm

#define STACK_WORDS                 8

#define EEBLE XS1_SR_EEBLE_MASK

#define move(dst, src) add dst, src, 0x0 

#define DPTR        r0
#define RXDV        r1
#define RXD         r2
#define PINS        r3
#define TMP1        r11
#define TMP2        r4
#define CRC         r5
#define IN_COUNTER  r6
#define PORT_LAST   r7


// {dptr, in_counter, port_this, crc}
// call: {unsigned* unsafe, unsigned, unsigned, unsigned} master_4x_pins_4b_body(unsigned * unsafe dptr,
//                                                                      in port p_mii_rxdv,
//                                                                      in buffered port:32 p_mii_rxd,
//                                                                      rmii_data_4b_pin_assignment_t rx_port_4b_pins,
//                                                                      unsigned * unsafe timestamp){

.globl master_4x_pins_4b_body_asm.nstackwords
.globl master_4x_pins_4b_body_asm.maxthreads
.globl master_4x_pins_4b_body_asm.maxtimers
.globl master_4x_pins_4b_body_asm.maxchanends
.globl master_4x_pins_4b_body_asm.maxsync
.type  master_4x_pins_4b_body_asm, @function
.linkset master_4x_pins_4b_body_asm.locnoside, 0
.linkset master_4x_pins_4b_body_asm.nstackwords, STACK_WORDS
.linkset master_4x_pins_4b_body_asm.maxchanends, 0
.linkset master_4x_pins_4b_body_asm.maxtimers, 0
.linkset master_4x_pins_4b_body_asm.maxthreads, 0
.linkset master_4x_pins_4b_body_asm.maxsync, 0

.globl master_4x_pins_4b_body_asm


    .align 8
    .issue_mode dual
master_4x_pins_4b_body_asm:
    DUALENTSP_lu6 STACK_WORDS

    std r4, r5, sp[0]   // Save r4 and r5
    std r6, r7, sp[1]

    // receive preamble
    in TMP1, res[RXD]
    ldw CRC, cp[initial_crc]
    ldc IN_COUNTER, 0
    in TMP2, res[RXD]
    unzip TMP2, TMP1, 0x1

    // swap results if use_lower
    bt PINS, use_lower
    move(TMP2, TMP1)
use_lower:
    // Load in expected second half of preamble
    ldw TMP1, cp[Dall_fives]
    eq TMP1, TMP1, TMP2
    bt TMP1, preamble_ok
    // Corrupt CRC if not OK
    not CRC, CRC
preamble_ok:
    // Grab timestamp
    gettime TMP2
    ldw TMP1, sp[STACK_WORDS + 1]
    stw TMP2, TMP1[0]

    // Start select
    clre // clear all events
    // Init for RXDV
    eeu res[RXDV]
    ldc TMP1, 0
    setd res[RXDV], TMP1 // no condition
    setc res[RXDV], 0x11 // WHAT IS THIS? MAYBE pinseq 0?
    ldap TMP1, data_valid_deasserted
    setv res[RXDV], TMP1

    // Init for RXD
    eeu res[RXD]
    ldap TMP1, rx_data_received
    setv res[RXD], TMP1

    waiteu


data_valid_deasserted:
    in TMP1, res[RXDV]
    // returns {dptr, in_counter, port_this, crc}
    //DPTR already in R0
    move(r1, IN_COUNTER)
    move(r2, PORT_LAST)
    move(r3, CRC)

    bu rx_done

rx_data_received:
    in TMP2, res[RXD]
    bf IN_COUNTER, first_short_word
    unzip TMP2, PORT_LAST, 1
    bt PINS, lower_main
    move(TMP2, PORT_LAST)
lower_main:
    // Store and inc
    stw TMP2, DPTR[0]
    add DPTR, DPTR, 0x4
    // CRC
    ldw TMP1, cp[polynomial]
    crc32 CRC, TMP2, TMP1

    // toggle IN_COUTER
    ldc TMP1, 0x1
    xor IN_COUNTER, IN_COUNTER, TMP1

    waiteu

first_short_word:
    in PORT_LAST, res[RXD]
    
    // toggle IN_COUTER
    ldc TMP1, 0x1
    xor IN_COUNTER, IN_COUNTER, TMP1

    waiteu

rx_done:



    // clre // clear all events



    ldd r4, r5, sp[0]
    ldd r6, r7, sp[1]

    retsp  STACK_WORDS

    .align 4
.cc_bottom master_4x_pins_4b_body_asm.func
