// Copyright 2024-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>


    .section .cp.rodata,     "ac", @progbits
    .align 4
.cc_top rmiiconsts.data
    .globl polynomial

initial_crc:
    .word 0x9226F562
preamble_second:
    .word 0xD5555555
Minus_four:
    .word 0xFFFFFFFC
.cc_bottom rmiiconsts.data



.cc_top master_rx_pins_4b_body_asm.func, master_rx_pins_4b_body_asm

#define STACK_WORDS                 6

#define EEBLE XS1_SR_EEBLE_MASK

#define move(dst, src) add dst, src, 0x0

#define NUM_BYTES   r0  // Keeps track of size of frame
#define RXDV        r1  // Port resource ID
#define RXD         r2  // Port resource ID
#define PINS_USED   r3  // Upper 2b = 1, Lower 2b = 0
#define TMP1        r11
#define TMP2        r4
#define CRC         r5  // Calculated CRC
#define IN_COUNTER  r6  // Flag used to track data Rx phase
#define PORT_LAST   r7  // The last port value read (used in phase 1)
#define DPTR        r8  // The pointer to write next word to
#define WRENDPTR    r9  // End of writable buffer space

#define TIME_STAMP  sp[STACK_WORDS + 1]
#define WRAP_PTR    sp[STACK_WORDS + 2]
#define WR_END_PTR  sp[STACK_WORDS + 3]


// {num_rx_bytes, crc, dptr_new}
// call: {int, unsigned, unsigned* unsafe} master_4x_pins_4b_body(unsigned * unsafe dptr,
//                                                                      in port p_mii_rxdv,
//                                                                      in buffered port:32 p_mii_rxd,
//                                                                      rmii_data_4b_pin_assignment_t rx_port_4b_pins,
//                                                                      unsigned * unsafe timestamp,
//                                                                      unsigned * unsafe wrap_ptr,
//                                                                      unsigned * unsafe write_end_ptr){

.globl master_rx_pins_4b_body_asm.nstackwords
.globl master_rx_pins_4b_body_asm.maxthreads
.globl master_rx_pins_4b_body_asm.maxtimers
.globl master_rx_pins_4b_body_asm.maxchanends
.globl master_rx_pins_4b_body_asm.maxsync
.type  master_rx_pins_4b_body_asm, @function
.linkset master_rx_pins_4b_body_asm.locnoside, 0
.linkset master_rx_pins_4b_body_asm.nstackwords, STACK_WORDS
.linkset master_rx_pins_4b_body_asm.maxchanends, 0
.linkset master_rx_pins_4b_body_asm.maxtimers, 0
.linkset master_rx_pins_4b_body_asm.maxthreads, 0
.linkset master_rx_pins_4b_body_asm.maxsync, 0

.globl master_rx_pins_4b_body_asm


    .align 8
    .issue_mode dual
master_rx_pins_4b_body_asm:
    {dualentsp STACK_WORDS; clre}

    std r4, r5, sp[0]   // Save r4 and r5
    std r6, r7, sp[1]   // Save r6 and r7
    std r8, r9, sp[2]   // Save r8 and r9

    // I'm using r4, r6, r7, r11 in the preamble checking code and updating r5 with the CRC we should start with
    // r4: TMP2
    // r11: TMP1
    // r6: IN_COUNTER
    // r7: PORT_LAST
    // r5: CRC

    {mkmsk TMP2, 0x1;     eeu res[RXD]} // TMP2 = r4
    {setd    res[RXDV], TMP2; ldc CRC, 0}

    {setc    res[RXDV], 0x11 ;     ldc TMP2, 0}
    {in r6, res[RXDV]; ldap TMP1, preamble_rx_data_received}

    {eeu res[RXDV]; ldw WRENDPTR, WR_END_PTR} // Keep write end value in register
    {setv res[RXD], TMP1 ; move(DPTR, NUM_BYTES)}
    {setd res[RXDV], TMP2; ldap TMP1, data_valid_deasserted} // Move first argument (r0 -> NUM_BYTES) to DPTR. r0 is free now
    ldw NUM_BYTES, cp[Minus_four]       // Start count at -4 (CRC not included)
    {setv res[RXDV], TMP1; ldc TMP2, 4}


not_last_preamble_word:
    ldw r7, cp[preamble_second] // r11: prev word, r6: current word
    add r11, r6, 0
    waiteu

preamble_rx_data_received:
    {in r6, res[RXD]; sub TMP2, TMP2, 1}
    bt r4, not_last_preamble_word
    unzip r6, r11, 0x1

    {bt PINS_USED, use_upper_bits; eq r6, r6, r7}
    eq r6, r11, r7 // USE_LOWER_2B: swap upper/lower
use_upper_bits:
    ldw CRC, cp[initial_crc] // Compare with expected preamble
    bt r6, after_preamble
preamble_not_match:
    not CRC, CRC // Start with corrupt CRC


after_preamble:
    // Make use of time here between INs by setting up stuff used later - we have 160ns or 12 slots at 75MHz
    // Grab timestamp and store
    {gettime TMP2; ldw TMP1, TIME_STAMP}
    {stw TMP2, TMP1[0]; ldap TMP1, rx_data_received} // load vector addr
////////////////// Start select /////////////////////
    // Init port resources
    {setv res[RXD], TMP1; ldc IN_COUNTER, 0} // init IN_COUNTER
    waiteu

//// Select case /////
data_valid_deasserted:
    // return {num_rx_bytes(r0), crc(r1), dptr_new(r2)}
    // NUM_BYTES already in r0
    // CRC remains in r5 and will be moved to r1 at the end
    {in r11, res[RXDV]; bf CRC, tail_0_and_the_end}

    // r11, r4 , r9, r1 are free to use at this point
    endin r4, res[RXD]  // r4: bits_left_in_port, r1: polynomial
    ldw r1, cp[polynomial]
    {bf r4, no_bits_left_in_port; in r11, res[RXD]} // r11: port_residual, r7: PORT_LAST
    bf IN_COUNTER, tail_1
tail_3:
    {shl r7, r7, 16; add NUM_BYTES, NUM_BYTES, 3} // port_last << 16
    unzip r11, r7, 1
    bt PINS_USED, tail_3_upper_bits
    add r11, r7, 0 // USE_LOWER_2B: swap upper/lower
tail_3_upper_bits:
    {shr r11, r11, 8; ldc r9, 24}
    crcn CRC, r11, r1, r9
    {move(r1, CRC); move(r2, DPTR)} // Move into the correct registers before returning
    ldd r4, r5, sp[0]
    ldd r6, r7, sp[1]
    ldd r8, r9, sp[2]
    retsp  STACK_WORDS

tail_1:
    {ldc r7, 0; add NUM_BYTES, NUM_BYTES, 1}
    unzip r11, r7, 1
    bt PINS_USED, tail_1_upper_bits
    add r11, r7, 0 // USE_LOWER_2B: swap upper/lower
tail_1_upper_bits:
    {shr r11, r11, 24; ldc r9, 8}
    crcn CRC, r11, r1, r9
    {move(r1, CRC); move(r2, DPTR)} // Move into the correct registers before returning
    ldd r4, r5, sp[0]
    ldd r6, r7, sp[1]
    ldd r8, r9, sp[2]
    retsp  STACK_WORDS

no_bits_left_in_port:
bf IN_COUNTER, tail_0_and_the_end
tail_2:
    {ldc r11, 0; add NUM_BYTES, NUM_BYTES, 2}
    unzip r7, r11, 1
    bt PINS_USED, tail_2_upper_bits
    add r7, r11, 0 // USE_LOWER_2B: swap upper/lower
tail_2_upper_bits:
    {shr r7, r7, 16; ldc r9, 16}
    crcn CRC, r7, r1, r9
tail_0_and_the_end:
    {move(r1, CRC); move(r2, DPTR)} // Move into the correct registers before returning
    ldd r4, r5, sp[0]
    ldd r6, r7, sp[1]
    ldd r8, r9, sp[2]
    retsp  STACK_WORDS

//// Select case /////
rx_data_received:
    // We need to receive two 32b port buffers for each 32b data. So there are two phases to this select case
    {in TMP2, res[RXD];     bf IN_COUNTER, first_short_word} // Grab the value and branch to the correct phase
    unzip TMP2, PORT_LAST, 1
    bt PINS_USED, upper_bits_main
    move(TMP2, PORT_LAST) // Swap upper/lower

upper_bits_main:
    ldw TMP1, cp[polynomial]     // First load polynomial
    crc32 CRC, TMP2, TMP1        // Do CRC.
    // See if we have hit the write end pointer
    {eq TMP1, WRENDPTR, DPTR;  ldc IN_COUNTER, 0x0}  // toggle IN_COUNTER
    {bt TMP1, rx_data_end; add NUM_BYTES, NUM_BYTES, 0x4}
    // If not, store the word and increment DPTR
    {stw TMP2, DPTR[0]; add DPTR, DPTR, 0x4}            // The increment will happen after the store

rx_data_end:
    waiteu

first_short_word:
    // Store PORT_LAST for next time around when we will re-construct the data word and load WRAP_PTR
    {ldw TMP1, WRAP_PTR ; move(PORT_LAST, TMP2)}
    // Toggle IN_COUNTER and compare to see if we have hit END_PTR
    {ldc IN_COUNTER, 0x1; eq TMP1, TMP1, DPTR}
    bf TMP1, first_short_word_end // If not, branch to the end
    // Dereference the DPTR and load it into DPTR. We have wrapped..
    ldw DPTR, DPTR[0]

first_short_word_end:
    waiteu

.cc_bottom master_rx_pins_4b_body_asm.func
