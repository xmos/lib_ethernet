#include <xs1.h>

    .section .cp.rodata,     "ac", @progbits
    .align 4
.cc_top rmiiconsts.data
initial_crc:
    .word 0x9226F562
expected_preamble:
    .word 0xD5555555
inverted_crc:
    .word 0x6DD90A9D
.cc_bottom rmiiconsts.data

.cc_top receive_full_preamble_4b_with_select_asm.func, receive_full_preamble_4b_with_select_asm

#define STACK_WORDS                 2

//Call: unsigned receive_full_preamble_4b_with_select(in port p_mii_rxdv,
                                              // in buffered port:32 p_mii_rxd,
                                              // rmii_data_4b_pin_assignment_t rx_port_4b_pins)
// r0: p_mii_rxdv
// r1: p_mii_rxd
// r2: rx_port_4b_pins

.globl receive_full_preamble_4b_with_select_asm.nstackwords
.globl receive_full_preamble_4b_with_select_asm.maxthreads
.globl receive_full_preamble_4b_with_select_asm.maxtimers
.globl receive_full_preamble_4b_with_select_asm.maxchanends
.globl receive_full_preamble_4b_with_select_asm.maxsync
.type  receive_full_preamble_4b_with_select_asm, @function
.linkset receive_full_preamble_4b_with_select_asm.locnoside, 0
.linkset receive_full_preamble_4b_with_select_asm.nstackwords, STACK_WORDS
.linkset receive_full_preamble_4b_with_select_asm.maxchanends, 0
.linkset receive_full_preamble_4b_with_select_asm.maxtimers, 0
.linkset receive_full_preamble_4b_with_select_asm.maxthreads, 0
.linkset receive_full_preamble_4b_with_select_asm.maxsync, 0

.globl receive_full_preamble_4b_with_select_asm
    .align 8
    .issue_mode dual
receive_full_preamble_4b_with_select_asm:
    DUALENTSP_lu6 STACK_WORDS
    {mkmsk r3, 0x1;     clre }

    {setd    res[r0], r3; stw r4, sp[0x0]}
    eeu res[r1]
    {setc    res[r0], 0x11 ;     ldc r4, 0}
    {in r3, res[r0]; ldap r11, rx_data_received}

    eeu res[r0]
    setv res[r1], r11

    setd res[r0], r4
    ldap r11, data_valid_deasserted
    {setv res[r0], r11; ldc r4, 4}

not_last_word:
    add r11, r3, 0 // r11: prev word, r3: current word
    waiteu
rx_data_received:
    {in r3, res[r1]; sub r4, r4, 1}

    bt r4, not_last_word
    unzip r3, r11, 0x1
    ldw r0, cp[expected_preamble]
    bt r2, use_upper_bits
    add r3, r11, 0 // swap upper/lower
use_upper_bits:
    {eq r0, r3, r0 ; ldw r4, sp[0]}
    bf r0, preamble_not_match
    ldw r0, cp[initial_crc]
    retsp STACK_WORDS

preamble_not_match:
    ldw r0, cp[inverted_crc]
    retsp STACK_WORDS

data_valid_deasserted:
    in r1, res[r0]
    {ldc r0, 0x0; ldw r4, sp[0]}

    retsp STACK_WORDS



.cc_bottom receive_full_preamble_4b_with_select_asm.func
