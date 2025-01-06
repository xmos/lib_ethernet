#include <xs1.h>

    .section .cp.rodata,     "ac", @progbits
    .align 4
.cc_top rmiiconsts.data
    .globl polynomial

initial_crc:
    .word 0x9226F562
preamble_second:
    .word 0xD5555555
inverted_crc:
    .word 0x6DD90A9D
Minus_four:
    .word 0xFFFFFFFC
.cc_bottom rmiiconsts.data

.cc_top master_rx_pins_1b_body_asm.func, master_rx_pins_1b_body_asm

#define STACK_WORDS 6


#define DPTR                r0  // The pointer to write next word to
#define RXDV                r1  // Port resource ID
#define RXD0                r2  // Port resource ID
#define RXD1                r3  // Port resource ID
#define TMP1                r11
#define TMP2                r4
#define TMP3                r7
#define CRC                 r5  // Calculated CRC
#define PORT_SHIFT_COUNT    r6  // Flag used to track data Rx phase

#define NUM_BYTES           r8  //Keeps track of size of frame
#define WRENDPTR            r9  // End of writable buffer space

#define TIME_STAMP  sp[STACK_WORDS + 1]
#define WRAP_PTR    sp[STACK_WORDS + 2]
#define WR_END_PTR  sp[STACK_WORDS + 2]

//{dptr, crc, num_rx_bytes} -> {r0, r1, r2}
//{unsigned* unsafe, unsigned, unsigned}  master_rx_pins_1b_body( unsigned * unsafe dptr,
//                                                                in port p_mii_rxdv,
//                                                                in buffered port:32 p_mii_rxd_0,
//                                                                in buffered port:32 p_mii_rxd_1,
//                                                                unsigned * unsafe timestamp,
//                                                                unsigned * unsafe wrap_ptr,
//                                                                unsigned * unsafe end_ptr
//                                                                )

.globl master_rx_pins_1b_body_asm.nstackwords
.globl master_rx_pins_1b_body_asm.maxthreads
.globl master_rx_pins_1b_body_asm.maxtimers
.globl master_rx_pins_1b_body_asm.maxchanends
.globl master_rx_pins_1b_body_asm.maxsync
.type  master_rx_pins_1b_body_asm, @function
.linkset master_rx_pins_1b_body_asm.locnoside, 0
.linkset master_rx_pins_1b_body_asm.nstackwords, STACK_WORDS
.linkset master_rx_pins_1b_body_asm.maxchanends, 0
.linkset master_rx_pins_1b_body_asm.maxtimers, 0
.linkset master_rx_pins_1b_body_asm.maxthreads, 0
.linkset master_rx_pins_1b_body_asm.maxsync, 0

.globl master_rx_pins_1b_body_asm
    .align 8
    .issue_mode dual
master_rx_pins_1b_body_asm:
    DUALENTSP_lu6 STACK_WORDS

    std r4, r5, sp[0]   // Save r4 and r5
    std r6, r7, sp[1]   // Save r6 and r7
    std r8, r9, sp[2]   // Save r8 and r9

    {clre; mkmsk TMP2, 1}
    eeu res[RXD0]
    {ldap TMP1, preamble_data_received;     setd res[RXDV], TMP2}
    setv res[RXD0], TMP1

    {setc res[RXDV], 0x11; ldc TMP2, 0}
    {in TMP1, res[RXDV]; ldw WRENDPTR, WR_END_PTR}
    eeu res[RXDV]

    {setd res[RXDV], TMP2; ldap TMP1, data_valid_deasserted}
    {setv res[RXDV], TMP1; ldw NUM_BYTES, cp[Minus_four]}
    waiteu

preamble_data_received:
    in TMP2, res[RXD0]
    in TMP3, res[RXD1]
    ldw TMP1, cp[preamble_second]
    zip TMP3, TMP2, 0x0
    {eq TMP1, TMP3, TMP1; ldw CRC, cp[initial_crc]}
    bt TMP1, after_preamble
    ldw CRC, cp[inverted_crc]   // Preamble doesn't match

after_preamble:
    // Grab timestamp and store
    {gettime TMP2; ldw TMP1, TIME_STAMP}
    {stw TMP2, TMP1[0]; ldc PORT_SHIFT_COUNT, 16}
    setpsc res[RXD0], PORT_SHIFT_COUNT
    setpsc res[RXD1], PORT_SHIFT_COUNT

    // Init port resources
    ldap TMP1, rx_data_received // load vector addr
    setv res[RXD0], TMP1
    waiteu

rx_data_received:
    in TMP1, res[RXD0]
    {in TMP2, res[RXD1]; ldw TMP3, cp[polynomial]}
    zip TMP2, TMP1, 0
    crc32 CRC, TMP2, TMP3
    // See if we have hit the write end pointer
    {eq TMP3, WRENDPTR, DPTR; ldw TMP1, WRAP_PTR }
    {bt TMP3, rx_data_end; add NUM_BYTES, NUM_BYTES, 0x4}
    // If not, store the word and increment DPTR
    {stw TMP2, DPTR[0]; add DPTR, DPTR, 0x4}            // The increment will happen after the store
    {eq TMP1, TMP1, DPTR; setpsc res[RXD0], PORT_SHIFT_COUNT}
    {bf TMP1, rx_data_end; setpsc res[RXD1], PORT_SHIFT_COUNT}
    // Dereference the DPTR and load it into DPTR. We have wrapped..
    ldw DPTR, DPTR[0]

rx_data_end:
    waiteu

data_valid_deasserted:
    {in TMP1, res[RXDV]; add r2, NUM_BYTES, 0}
    // DPTR is already in r0
    add r1, CRC, 0
    ldd r4, r5, sp[0]
    ldd r6, r7, sp[1]
    ldd r8, r9, sp[2]
    retsp  STACK_WORDS



.cc_bottom master_rx_pins_1b_body_asm.func
