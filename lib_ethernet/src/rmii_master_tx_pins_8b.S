// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

    .section .cp.rodata,     "ac", @progbits
    .align 4
.cc_top tx8consts.data
preamble_first:
    .word 0x55555555    
preamble_second:
    .word 0xD5555555
.cc_bottom tx8consts.data

#include <xs1.h>

#define STACK_WORDS                 6

//Call: void rmii_master_tx_pins_8b_asm(unsigned * unsafe dptr,
//                                      int byte_count,
//                                      out buffered port:32 p_mii_txd,
//                                      unsigned lookup_8b_tx[256],
//                                      unsigned poly,
//                                      unsigned * unsafe wrap_start_ptr,
//                                      int byte_count_wrapped);

#define DPTR                        r0
#define NUM_BYTES                   r1 
#define PORT_RES_ID                 r2
#define LOOKUP                      r3
#define POLY_PASSED_IN              sp[STACK_WORDS+1]
#define WRAP_START_PTR_PASSED_IN    sp[STACK_WORDS+2]
#define WRAP_SZ_PASSED_IN           sp[STACK_WORDS+3] // 0 or positive
#define CRC                         r4
#define POLY                        r5
#define TMP1                        r6
#define TMP2                        r7
#define COUNTER                     r8
#define TMP4                        r9
#define TMP3                        r11


.cc_top rmii_master_tx_pins_8b_asm.func, rmii_master_tx_pins_8b_asm


.globl rmii_master_tx_pins_8b_asm.nstackwords
.globl rmii_master_tx_pins_8b_asm.maxthreads
.globl rmii_master_tx_pins_8b_asm.maxtimers
.globl rmii_master_tx_pins_8b_asm.maxchanends
.globl rmii_master_tx_pins_8b_asm.maxsync
.type  rmii_master_tx_pins_8b_asm, @function
.linkset rmii_master_tx_pins_8b_asm.locnoside, 0
.linkset rmii_master_tx_pins_8b_asm.nstackwords, STACK_WORDS
.linkset rmii_master_tx_pins_8b_asm.maxchanends, 0
.linkset rmii_master_tx_pins_8b_asm.maxtimers, 0
.linkset rmii_master_tx_pins_8b_asm.maxthreads, 0
.linkset rmii_master_tx_pins_8b_asm.maxsync, 0

.globl rmii_master_tx_pins_8b_asm

    .align 8
    .issue_mode dual
rmii_master_tx_pins_8b_asm:
    DUALENTSP_lu6 STACK_WORDS

    std r4, r5, sp[0]   // Save r4 and r5
    std r6, r7, sp[1]   // Save r6 and r7
    std r8, r9, sp[2]   // Save r8 and r9

    ldc CRC, 0
    ldw POLY, sp[STACK_WORDS+1]


tx_8_first_preamble:
    // First preamble
    mkmsk TMP1, 8
    ldw TMP2, cp[preamble_first]
    and TMP3, TMP2, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3
    shr TMP2, TMP2, 8
    and TMP3, TMP2, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3
    shr TMP2, TMP2, 8
    and TMP3, TMP2, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3
    shr TMP2, TMP2, 8
    and TMP3, TMP2, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3 // Ideally get to next OUT 6 slots later

    // Do second preamble
tx_8_second_preamble:
    ldw TMP2, cp[preamble_second]
    and TMP3, TMP2, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3
    shr TMP2, TMP2, 8
    and TMP3, TMP2, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3
    shr TMP2, TMP2, 8
    and TMP3, TMP2, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3
    shr TMP2, TMP2, 8
    and TMP3, TMP2, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3 // Ideally get to loop OUT 6 slots later

#define BYTE_TO_TX      TMP1
#define EXPANDED_WORD   TMP3
#define WRAP_SIZE       TMP4

    // Special case for first word because we need to NOT the data value for the CRC
tx_8_first_word:
    {ldw TMP2, DPTR[0]; mkmsk TMP4, 8}
    and BYTE_TO_TX, TMP2, TMP4
    ldw EXPANDED_WORD, LOOKUP[BYTE_TO_TX]
    {out res[PORT_RES_ID], EXPANDED_WORD; shr TMP2, TMP2, 8}
    and BYTE_TO_TX, TMP2, TMP4
    ldw EXPANDED_WORD, LOOKUP[BYTE_TO_TX]
    {out res[PORT_RES_ID], EXPANDED_WORD; shr TMP2, TMP2, 8}
    and BYTE_TO_TX, TMP2, TMP4
    ldw EXPANDED_WORD, LOOKUP[BYTE_TO_TX]
    {out res[PORT_RES_ID], EXPANDED_WORD; shr TMP2, TMP2, 8}
    {and BYTE_TO_TX, TMP2, TMP4; ldw TMP2, DPTR[0]}         // Now reload the data word since it has been shidted away
    {ldw EXPANDED_WORD, LOOKUP[BYTE_TO_TX]; not TMP2, TMP2} // Invert it
    crc32 CRC, TMP2, POLY                                   // And CRC it            
    {out res[PORT_RES_ID], EXPANDED_WORD; ldw WRAP_SIZE, WRAP_SZ_PASSED_IN} // Out final word and load in the wrap size


#define BREAK_LOOP      TMP2

    // Do main body
tx8_main_loop_init:
    ldc COUNTER, 4 // We have already sent a word
    {ld8u BYTE_TO_TX, DPTR[COUNTER]; add COUNTER, COUNTER, 1} // Load initial byte to tx + Inital increment

tx8_main_loop:
    {ldw EXPANDED_WORD, LOOKUP[BYTE_TO_TX]; eq BREAK_LOOP, COUNTER, NUM_BYTES}
    crc8 CRC, BYTE_TO_TX, BYTE_TO_TX, POLY // This trashes BYTE_TO_TX with BYTE_TO_TX >> 8 but we don't care now
    {out res[PORT_RES_ID], EXPANDED_WORD; ld8u BYTE_TO_TX, DPTR[COUNTER]}
    {add COUNTER, COUNTER, 1; bf BREAK_LOOP, tx8_main_loop}

tx_8_wrap_loop_check_and_init:
    {bf WRAP_SIZE, tx8_crc; ldc COUNTER, 0}
    ldw DPTR, WRAP_START_PTR_PASSED_IN
    {ld8u BYTE_TO_TX, DPTR[COUNTER]; add COUNTER, COUNTER, 1}

tx8_wrap_loop:
    {ldw EXPANDED_WORD, LOOKUP[BYTE_TO_TX]; eq BREAK_LOOP, COUNTER, WRAP_SIZE}
    crc8 CRC, BYTE_TO_TX, BYTE_TO_TX, POLY // This trashes BYTE_TO_TX with BYTE_TO_TX >> 8 but we don't care now
    {out res[PORT_RES_ID], EXPANDED_WORD; ld8u BYTE_TO_TX, DPTR[COUNTER]}
    {add COUNTER, COUNTER, 1; bf BREAK_LOOP, tx8_wrap_loop}

tx8_crc:
    // CRC. CRC gets shifted away but we don't care now
    {mkmsk TMP1, 8; mkmsk TMP2, 32} // Load byte mask and 0xFFFFFFFF for final CRC calc
    crc32 CRC, TMP2, POLY
    and TMP3, CRC, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3      // Must get here 6 slots after last loop OUT
    shr CRC, CRC, 8
    and TMP3, CRC, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3
    shr CRC, CRC, 8
    and TMP3, CRC, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3
    shr CRC, CRC, 8
    and TMP3, CRC, TMP1
    ldw TMP3, LOOKUP[TMP3]
    out res[PORT_RES_ID], TMP3

    ldd r4, r5, sp[0]
    ldd r6, r7, sp[1]
    ldd r8, r9, sp[2]

    retsp  STACK_WORDS



.cc_bottom rmii_master_tx_pins_8b_asm.func
