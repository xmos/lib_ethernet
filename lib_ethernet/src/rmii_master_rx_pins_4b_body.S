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

#define STACK_WORDS                 4

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
//                                                                      unsigned * unsafe timestamp,
//                                                                      unsigned * unsafe wrap_ptr){

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
    std r6, r7, sp[1]   // Save r6 and r7

    // receive preamble second half (32b data = 64b port bits)
    {in PORT_LAST, res[RXD];    ldw CRC, cp[initial_crc]}
    
    // Make use of time here between INs by setting up stuff used later - we have 160ns or 12 instuctions at 75MHz
    {ldc IN_COUNTER, 0;         clre}   // clear all events ahead of select and init IN_COUNTER
    ldw TMP1, cp[Dall_fives]            // Load expected second half of preamble
    eeu res[RXDV]                       // Start setup for select early
    eeu res[RXD]

    // Grab the second 32b port of the preamble second half
    in TMP2, res[RXD]
    unzip TMP2, PORT_LAST, 0x1

    // swap results if PINS set to zero (USE_LOWER)
    bt PINS, use_upper
    move(TMP2, PORT_LAST) // Swap upper/lower

use_upper:
    // Check received preamable against expected
    eq TMP1, TMP1, TMP2 // Check OK?
    bt TMP1, preamble_ok
    not CRC, CRC     // Corrupt CRC if not OK

preamble_ok:
    // Grab timestamp and store
    {gettime TMP2 ; ldw TMP1, sp[STACK_WORDS + 1]}
    stw TMP2, TMP1[0]

//////// Start select //////
    // Init port resources
    {setd res[RXDV], IN_COUNTER; ldap TMP1, data_valid_deasserted} // no condition. IN_COUNTER happens to be 0 at this point so re-use
    setv res[RXDV], TMP1
    {setc res[RXDV], 0x11; ldap TMP1, rx_data_received}            // Set pinseq0 event and load vector addr
    setv res[RXD], TMP1

    waiteu

//// Select case /////
data_valid_deasserted:
    {in TMP1, res[RXDV];    move(r1, IN_COUNTER)} // Complete the IN and start setting up returns
    // returns {dptr, in_counter, port_this, crc} so setup registers for this
    // DPTR already in R0
    {move(r2, PORT_LAST);   move(r3, CRC)}

    // Restore previous regs before return
    ldd r4, r5, sp[0]
    ldd r6, r7, sp[1]

    retsp  STACK_WORDS

//// Select case /////
rx_data_received:
    // We need to receive two 32b port buffers for each 32b data. So there are two phases to this select case 
    {in TMP2, res[RXD];     bf IN_COUNTER, first_short_word} // Grab the value and branch to the correct phase
    unzip TMP2, PORT_LAST, 1
    bt PINS, upper_bit_main
    move(TMP2, PORT_LAST) // Swap upper/lower

upper_bit_main:
    // Just store and set the counter
    {stw TMP2, DPTR[0]; add DPTR, DPTR, 0x4}            // The increment will happen after the store
    {ldw TMP1, cp[polynomial]; ldc IN_COUNTER, 0x0}     // First load polynomial and toggle IN_COUTER
    crc32 CRC, TMP2, TMP1                               // Do CRC.
    nop
    nop

    waiteu

first_short_word:
    // Store for next time around when we will re-construct the data word
    {move(PORT_LAST, TMP2) ;ldc IN_COUNTER, 0x1}
    nop
    nop
    nop
    nop
    nop
    nop

    waiteu

.cc_bottom master_4x_pins_4b_body_asm.func
