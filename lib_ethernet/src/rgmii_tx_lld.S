// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include "xs1.h"
#include "mii_buffering_defines.h"

#if (ETHERNET_MAX_PACKET_SIZE != 1518)
#error "The RGMII TX code is written for maximum 1518 byte packets. Must be modified for other packet sizes."
#endif

// Register allocation. Don't re-map r11 as some instructions must write to it
#define tmp5      r0
#define p_txd     r1
#define base      r2
#define ptr       r3
#define crc       r4
#define poly      r5
#define tmp6      r6
#define tmp1      r7
#define tmp2      r8
#define tmp3      r9
#define tmp4      r10

// Stack offsets
#define SP_CHAN_ID        1
#define SP_MOD3_TABLE     2
#define SP_DP_VALUE       3
#define SP_REGISTER_SAVE  4
#define SP_NUM_WORDS     11+1 // Extend to even number to conform to XS2 ABI

#define MAX_PACKET_WORDS (ETHERNET_MAX_PACKET_SIZE/4)

#if defined(__XS2A__)
.align 4
.section .dp.data, "awd", @progbits
.cc_top txconsts.data
data_values:
.word 0x55555555
.word 0xd5555555
.word (MAX_PACKET_WORDS * 2)
.cc_bottom txconsts.data

.text
        .cc_top rgmii_tx_lld.function
        .set    rgmii_tx_lld.nstackwords,SP_NUM_WORDS
        .globl  rgmii_tx_lld.nstackwords
        .set    rgmii_tx_lld.maxcores,1
        .globl  rgmii_tx_lld.maxcores
        .set    rgmii_tx_lld.maxtimers,0
        .globl  rgmii_tx_lld.maxtimers
        .set    rgmii_tx_lld.maxchanends,0
        .globl  rgmii_tx_lld.maxchanends

        .globl  rgmii_tx_lld
        .align  4
        .type   rgmii_tx_lld,@function
        .issue_mode dual
rgmii_tx_lld:
        dualentsp SP_NUM_WORDS

        // Save off all callee state
        stw  r4, sp[SP_REGISTER_SAVE + 0]
        stw  r5, sp[SP_REGISTER_SAVE + 1]
        stw  r6, sp[SP_REGISTER_SAVE + 2]
        stw  r7, sp[SP_REGISTER_SAVE + 3]
        stw  r8, sp[SP_REGISTER_SAVE + 4]
        stw  r9, sp[SP_REGISTER_SAVE + 5]
        stw r10, sp[SP_REGISTER_SAVE + 6]

        // Setup an event for the case of mode change
        ldap r11, tx_speed_change_handler
        setv res[r2], r11
        eeu res[r2]
        setsr XS1_SR_EEBLE_SET(0, 1)

        bu start_gigabit_tx

tx_speed_change_handler:
        // Consume the data causing the interrupt
        get r11, ed
        in r11, res[r11]

        // Restore the DP
        ldw dp, sp[SP_DP_VALUE]

        // Restore and return
        ldw  r4, sp[SP_REGISTER_SAVE + 0]
        ldw  r5, sp[SP_REGISTER_SAVE + 1]
        ldw  r6, sp[SP_REGISTER_SAVE + 2]
        ldw  r7, sp[SP_REGISTER_SAVE + 3]
        ldw  r8, sp[SP_REGISTER_SAVE + 4]
        ldw  r9, sp[SP_REGISTER_SAVE + 5]
        ldw r10, sp[SP_REGISTER_SAVE + 6]

        retsp SP_NUM_WORDS

start_gigabit_tx:
        // Save off the DP which will be used later
        stw dp, sp[SP_DP_VALUE]

        // Put core in fast mode and ensure that the core remains in dual
        // issue when an interrupt is taken
        setsr XS1_SR_FAST_SET(XS1_SR_KEDI_SET(0, 1), 1)

        // TX expects channel ID in tmp6  // Store the channel ID on the stack
        { mov tmp6, tmp5                  ; stw tmp5, sp[SP_CHAN_ID] }

        // Setup the CRC polynomial
        ldap r11, crc_poly
        ldw poly, r11[0]

        // Setup the RXD data pattern (SOF)
        ldap r11, sof_value
        ldw r11, r11[0]
        setd res[p_txd], r11

        // Load data_values pointer into DP
        ldap r11, data_values
        stw r11, sp[2]
        ldw dp, sp[2]

        // Put the mod3_table on the stack so that it can be restored
        // using a short instruction
        ldap r11, mod3_table
        stw r11, sp[SP_MOD3_TABLE]

.align 16
tx_sof:
        // Get address of packet buffer   // Timestamp the start of packet
        { in base, res[tmp6]              ; gettime tmp5 }

        // Load constant for bit mask     // Load byte count from packet structure
        { ldc tmp6, 0x3                   ; ldw tmp4, base[0] }

        // Compute number of end bytes    // Save the timestamp to the packet
        { and tmp6, tmp4, tmp6            ; stw tmp5, base[1] }

        // Convert bytes to bits          // Get word count
        { shl tmp5, tmp6, 3               ; shr tmp2, tmp4, 2 }

        // Load size of mii_packet_t header // Load the offset for the start sequence
        { ldc ptr, MII_PACKET_HEADER_BYTES; ld8u tmp6, r11[tmp2] }

        // Skip mii_packet_t header
        { add ptr, base, ptr              ; nop }

        // Two insts per data word        // Load in the max packet size branch distance
        { shl tmp4, tmp2, 1               ; ldw tmp1, dp[2] }

        // Compute start in unrolled code // Branch to relevant start sequence
        { sub tmp4, tmp1, tmp4            ; bru tmp6 }
bru_from:

        // Three possible start sequences depending on the word alignment
        // Each one pre-loads three data words so that the end sequence
        // can run with only one instruction between OUTs
.align 16
start_zero:
        { add ptr, ptr, 4                 ; ldw tmp1, ptr[0] }
        { not crc, tmp1                   ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { nop                             ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        bu start

start_one:
        { add ptr, ptr, 4                 ; ldw tmp2, ptr[0] }
        { not crc, tmp2                   ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { nop                             ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        bu start

start_two:
        { add ptr, ptr, 4                 ; ldw tmp3, ptr[0] }
        { not crc, tmp3                   ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { nop                             ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        bu start

// Ensure the alignment of the two instructions in the core loop remains fixed
.align 16
start:
        // Compute branch distance        // Load first preamble word
        { nop                             ; ldw tmp6, dp[0] }

        // Send first preamble word       // Load second preamble word
        { out res[p_txd], tmp6            ; ldw tmp6, dp[1] }

        // Send second preamble word      // Load constant to be used as final CRC step
        { out res[p_txd], tmp6            ; ldc r11, 0 }

        // Invert last CRC step constant  // Branch to correct location in code depending on packet size
        { not r11, r11                    ; bru tmp4 }

tx_data:
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4

        { out res[p_txd], tmp3            ; ldw tmp3, ptr[0] }
        crc32_inc crc, tmp3, poly, ptr, 4
        { out res[p_txd], tmp2            ; ldw tmp2, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { out res[p_txd], tmp1            ; ldw tmp1, ptr[0] }
        crcn crc, tmp1, poly, tmp5
        { out res[p_txd], tmp3            ; nop }
        crc32 crc, r11, poly
        //                                // Restore the mod3_table
        { out res[p_txd], tmp2            ; ldw r11, sp[SP_MOD3_TABLE] }
        linsert tmp2, tmp1, crc, tmp5, 32

        //                                // Restore the channel ID
        { out res[p_txd], tmp1            ; ldw tmp6, sp[SP_CHAN_ID] }

        // Signal this packet has been sent // Skip OUTPW if word-aligned
        { out res[tmp6], base             ; bf tmp5, tx_done }
        outpw res[p_txd], tmp2, tmp5

tx_done:
        // Must be a 32-bit instruction for long branch
        bu tx_sof
        .align 4

.align 4
// A table of branch distance using a modulo three of the word count. This selects
// the relevant start sequence depending on where in the unrolled code the sequence
// will start. There are 127 lines, each with 3 values, giving packet sizes up to
// 381 words (1524 bytes).
mod3_table:
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.byte (start_zero - bru_from) / 4, (start_one - bru_from) / 4, (start_two - bru_from) / 4
.cc_bottom rgmii_tx_lld.function

#else
        .cc_top rgmii_tx_lld.function
        .set    rgmii_tx_lld.nstackwords,0
        .globl  rgmii_tx_lld.nstackwords
        .set    rgmii_tx_lld.maxcores,0
        .globl  rgmii_tx_lld.maxcores
        .set    rgmii_tx_lld.maxtimers,0
        .globl  rgmii_tx_lld.maxtimers
        .set    rgmii_tx_lld.maxchanends,0
        .globl  rgmii_tx_lld.maxchanends

        .globl  rgmii_tx_lld
        .align  4
        .type   rgmii_tx_lld,@function
rgmii_tx_lld:
        .cc_bottom rgmii_tx_lld.function

#endif
