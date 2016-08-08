// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include "xs1.h"
#include "mii_buffering_defines.h"

// Register allocation. Don't re-map r11 as some instructions must write to it
#define chan      r0
#define p_rxd     r1
#define tmp5      r2
#define tmp4      r3
#define base      r4
#define ptr       r5
#define crc       r6
#define poly      r7
#define tmp1      r8
#define tmp2      r9
#define tmp3      r10

// Stack offsets - NOTE: SPC offset is fixed
#define SP_SPC              1
#define SP_PING_PONG        2
#define SP_VALID_LEN        3
#define SP_FIRST_WORD       4
#define SP_SAVED_WORD13     5
#define SP_REGISTER_SAVE_0  6
#define SP_REGISTER_SAVE_1  7
#define SP_REGISTER_SAVE_2  8
#define SP_REGISTER_SAVE_3  9
#define SP_REGISTER_SAVE_4 10
#define SP_REGISTER_SAVE_5 11
#define SP_REGISTER_SAVE_6 12
#define SP_NUM_WORDS       13+1 // Extend to even number to conform to XS2 ABI

#define SP_RX_ERR        (SP_NUM_WORDS + 3)
#define SP_RX_DV         (SP_NUM_WORDS + 2)

.section .dp.data, "awd", @progbits
.cc_top rxconsts.data

.align 4
.globl sof_value
sof_value:
.word 0xd5
.globl crc_poly
crc_poly:
.word 0xEDB88320

// The byte-reversed version of the tag
.globl vlan_prio_tag
vlan_prio_tag:
.word 0x0081

// The cutoff point between length and type in the Length/Type field
.globl max_packet_len
max_packet_len:
.word 1536

// The maximum number of bytes in a valid packet
.globl max_num_bytes
max_num_bytes:
.word ETHERNET_MAX_PACKET_SIZE

// Error counts
.align 4
.globl mii_count_crc_error
mii_count_crc_error:
.word 0
.globl mii_count_len_error
mii_count_len_error:
.word 0
.cc_bottom rxconsts.data

.text
#if defined(__XS2A__)
        .cc_top rgmii_rx_lld.function
        .set    rgmii_rx_lld.nstackwords,SP_NUM_WORDS
        .globl  rgmii_rx_lld.nstackwords
        .set    rgmii_rx_lld.maxcores,1
        .globl  rgmii_rx_lld.maxcores
        .set    rgmii_rx_lld.maxtimers,0
        .globl  rgmii_rx_lld.maxtimers
        .set    rgmii_rx_lld.maxchanends,0
        .globl  rgmii_rx_lld.maxchanends

        .globl  rgmii_rx_lld
        .align  4
        .type   rgmii_rx_lld,@function
        .issue_mode dual
rgmii_rx_lld:
        dualentsp SP_NUM_WORDS

        // Save off all callee state
        stw  r4, sp[SP_REGISTER_SAVE_0]
        stw  r5, sp[SP_REGISTER_SAVE_1]
        stw  r6, sp[SP_REGISTER_SAVE_2]
        stw  r7, sp[SP_REGISTER_SAVE_3]
        stw  r8, sp[SP_REGISTER_SAVE_4]
        stw  r9, sp[SP_REGISTER_SAVE_5]
        stw r10, sp[SP_REGISTER_SAVE_6]

        // Setup an event for the case of mode change
        ldap r11, rx_speed_change_handler
        setv res[r3], r11
        eeu res[r3]
        setsr XS1_SR_EEBLE_SET(0, 1)

        bu start_gigabit_rx

rx_speed_change_handler:
        // Consume the data causing the interrupt
        get r11, ed
        in r11, res[r11]

        // Restore and return
        ldw  r4, sp[SP_REGISTER_SAVE_0]
        ldw  r5, sp[SP_REGISTER_SAVE_1]
        ldw  r6, sp[SP_REGISTER_SAVE_2]
        ldw  r7, sp[SP_REGISTER_SAVE_3]
        ldw  r8, sp[SP_REGISTER_SAVE_4]
        ldw  r9, sp[SP_REGISTER_SAVE_5]
        ldw r10, sp[SP_REGISTER_SAVE_6]

        clrsr XS1_SR_ININT_SET(0,1)

        retsp SP_NUM_WORDS

start_gigabit_rx:
        // Put core in fast mode and ensure that the core remains in dual
        // issue when an interrupt is taken
        setsr XS1_SR_FAST_SET(XS1_SR_KEDI_SET(0, 1), 1)

        // Save off the ping pong channel
        { stw r1, sp[SP_PING_PONG]        ; mov tmp1, r1 }

        // Setup the CRC polynomial
        ldap r11, crc_poly
        ldw poly, r11[0]

        // Receive address of packet buffer // Get RXD off the stack
        { in base, res[chan]              ; ldw p_rxd, sp[SP_NUM_WORDS + 1] }

        // Compute the minimum valid packet size before 4 for the CRC
        ldc r11, 60 + 4
        stw r11, sp[SP_VALID_LEN]

        // Initially only one of the ping-pong threads must setup the ports and start
        bt r2, rx_sof

        // Setup the RXD data pattern (SOF)
        ldap r11, sof_value
        ldw r11, r11[0]
        setd res[p_rxd], r11

        // Setup the RXER port to detect the port going high
        { ldc r11, 1                      ; ldw tmp3, sp[SP_RX_ERR] }
        setd res[tmp3], r11
        ldap r11, rx_error
        setv res[tmp3], r11
        setc res[tmp3], XS1_SETC_IE_MODE_INTERRUPT
        eeu res[tmp3]
        setc res[tmp3], XS1_SETC_COND_EQ

        // Setup the RXDV data
        { ldc r11, 0                      ; ldw tmp4, sp[SP_RX_DV] }
        setd res[tmp4], r11
        ldap r11, rx_done
        setv res[tmp4], r11
        setc res[tmp4], XS1_SETC_IE_MODE_INTERRUPT
        eeu res[tmp4]

        // Initially only one of the ping-pong threads must setup the ports and start
        bu rx_dont_wait

rx_sof:
        { setsr XS1_SR_EEBLE_SET(0, 1)    ; bu rx_aligned }

.align 16
rx_aligned:
        // Wait for ownership in the ping-pong (assume tmp1 contains the channel ID)
        // and load RX_ERR into tmp3 so that it is available for the error handler code
        { in tmp1, res[tmp1]              ; ldw tmp3, sp[SP_RX_ERR] }

rx_dont_wait:
        // Take ownership of the error port // Offset of data within the mii_packet_t structure
        { setc res[tmp3], XS1_SETC_COND_EQ ; ldc ptr, MII_PACKET_HEADER_BYTES }

        // Setup the condition on the data port for the SOF
        // Load RX_DV into tmp4 so that it is available for the error handler code
        { setc res[p_rxd], XS1_SETC_COND_EQ ; ldw tmp5, sp[SP_RX_DV] }

        // Setup the condition on the data valid port for the EOF
                                           // Indicate that a minimum sized frame has not arrived yet
        { setc res[tmp5], XS1_SETC_COND_EQ ; ldc r11, 0 }

        // Wait for the SOF               // Read the timestamp
        { in tmp1, res[p_rxd]             ; gettime tmp2 }

        //                                // Store off the timestamp
        { setsr XS1_SR_IEBLE_SET(0, 1)    ; stw tmp2, base[1] }

rx_data:
        //                                // Don't store SOF (would overwrite timestamp)
        { in tmp1, res[p_rxd]             ; add ptr, base, ptr }

        //                                // Number of bits required for two INs after ENDIN
        { not crc, tmp1                   ; ldc tmp4, 33 }

        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp2, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp2, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; ldw r11, sp[SP_PING_PONG] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4
        { in tmp1, res[p_rxd]             ; stw tmp1, ptr[0] }
        crc32_inc crc, tmp1, poly, ptr, 4

        // Packet too large, throw it away as an error
        bu rx_error_too_long

.align 16
rx_runt:
        // Setup registers used by start of frame code // Restore the DV ID
        { setc res[p_rxd], XS1_SETC_RUN_CLRBUF ; ldw tmp4, sp[SP_RX_DV] }

        // Clear data from the DV port
        { in r11, res[tmp4]               ; ldw tmp3, sp[SP_RX_ERR] }

        // Runt received, just start next frame
        bu rx_dont_wait

.align 16
rx_done:
        // Release the last bytes in port // Restore ping-pong channel from stack
        { endin tmp3, res[p_rxd]          ; bf r11, rx_runt }

        // Consume data from port         // Determine whether to do second IN
        { in tmp5, res[p_rxd]             ; lss tmp4, tmp3, tmp4 }

        // Signal to ping-pong thread
        { out res[r11], r11               ; bt tmp4, rx_one_word_endin }

rx_two_word_endin:
        // Consume final bits             // Restore the DV ID
        { in r11, res[p_rxd]              ; ldw tmp4, sp[SP_RX_DV] }

        // Clear data from DV port        // Store off first word of data
        { in tmp4, res[tmp4]              ; stw tmp5, sp[SP_FIRST_WORD] }

        //                                // Store off SPC to use
        { mov tmp5, r11                   ; stw spc, sp[SP_SPC] }

        // Use the SPC to determine whether the CRC still needs to be done
        { ldc r11, 0x7                    ; ldw tmp4, sp[SP_SPC] }
        { and tmp4, tmp4, r11             ; stw tmp2, sp[SP_SAVED_WORD13] }
        { nop                             ; bf tmp4, rx_two_crc_done }

rx_two_do_crc:
        // Perform CRC for last word if required
        crc32_inc crc, tmp1, poly, ptr, 4

rx_two_crc_done:
        // Move pointer for last word     // Store off last complete word
        { ldc tmp4, 32                    ; stw tmp1, ptr[0] }

        // Compute actual ENDIN bytes     // Restore full word from ENDIN
        { sub tmp3, tmp3, tmp4            ; ldw tmp1, sp[SP_FIRST_WORD] }
        crc32_inc crc, tmp1, poly, ptr, 4

        { add ptr, ptr, 4                 ; stw tmp1, ptr[0] }
        { nop                             ; bu rx_shared }

.align 16
rx_one_word_endin:
        //                                // Restore DV ID
        { nop                             ; ldw tmp4, sp[SP_RX_DV]}

        // Clear data from DV port        // Store off SPC to use
        { in r11, res[tmp4]               ; stw spc, sp[SP_SPC] }

        // Use the SPC to determine whether the CRC still needs to be done
        { ldc r11, 0x7                    ; ldw tmp4, sp[SP_SPC] }
        { and tmp4, tmp4, r11             ; stw tmp2, sp[SP_SAVED_WORD13] }
        { nop                             ; bf tmp4, rx_one_crc_done }

rx_one_do_crc:
        // Perform CRC for last word if required
        crc32_inc crc, tmp1, poly, ptr, 4

rx_one_crc_done:
        // Move pointer for last word     // Store off last complete word
        { add ptr, ptr, 4                 ; stw tmp1, ptr[0] }


rx_shared:
        // Compute number of bytes so far // Minimum valid frame bytes
        { sub tmp2, ptr, base             ; ldw tmp4, sp[SP_VALID_LEN] }

        // Compute byte count from bits   //
        { shr r11, tmp3, 3                ; ldc tmp1, 32 }

        // Compute byte count received    // Compute shift distance to align data
        { add tmp2, tmp2, r11             ; sub r11, tmp1, tmp3 }

        // Align data word correctly      // Load mii_packet_t overhead
        { shr tmp1, tmp5, r11             ; ldc tmp5, MII_PACKET_HEADER_BYTES }
        crcn crc, tmp1, poly, tmp3

        // Discount mii_packet_t overhead
        { sub tmp2, tmp2, tmp5            ; nop }

        // Compare length with minimum    // Offset of length/type field
        { lss tmp4, tmp2, tmp4            ; ldc tmp1, MII_PACKET_HEADER_WORDS + 3 }

        // Test whether result is -1      // In case of under-sized frames
        { not crc, crc                    ; bt tmp4, rx_error_runt }

        //                                // Load the length/type field
        { mkmsk tmp5, 16                  ; ldw tmp1, base[tmp1] }

        //                                // Load the constant to compare against
        { and tmp1, tmp1, tmp5            ; ldw tmp3, dp[vlan_prio_tag] }

        //                                // Load the length/type field
        { eq tmp3, tmp1, tmp3             ; ldw tmp5, dp[max_packet_len] }

        // Packet overhead to discount    // Branch if this isn't vlan tagged
        { ldc tmp3, 18                    ; bf tmp3, rx_test_length }

        //                                // Offset of length/type field in VLAN tagged packet
        { nop                             ; ldc tmp1, MII_PACKET_HEADER_WORDS + 4 }

        //                                // Load the length/type field after a vlan tag
        { add tmp3, tmp3, 4               ; ldw tmp1, base[tmp1] }

rx_test_length:
        // Mask off the data              // Load the length/type field after a vlan tag
        { byterev tmp1, tmp1              ; sub tmp4, tmp2, tmp3 }

        // The length is a 16-bit field   // The word offset of the missing word
        { shr tmp1, tmp1, 16              ; ldc ptr, (MII_PACKET_HEADER_WORDS + 13) }

        // The byte offset of the missing word
        { shl ptr, ptr, 2                 ; nop }

        // Check whether type/len is a length // Restore the missing word to tmp5
        { lsu tmp3, tmp1, tmp5            ; ldw tmp5, sp[SP_SAVED_WORD13] }

        // Check whether the length is invalid (less than the actual data)
        { lsu tmp3, tmp4, tmp1            ; bf tmp3, rx_test_max_len }

        { nop                             ; bt tmp3, rx_length_error }

rx_test_max_len:
        // Ignore crc word in byte count  // Load the maximum permissible length
        { sub tmp2, tmp2, 4               ; ldw tmp3, dp[max_num_bytes] }

        // Compare actual length with max // If crc is wrong then return pointer
        { lsu tmp3, tmp3, tmp2            ; bt crc, rx_error_crc }

        // Compute address of the missing word // If the packet is too long then bin it
        { add ptr, base, ptr              ; bt tmp3, rx_length_error }

rx_crc_ok:
        // CRC ok, send pointer           // Store size in word 0 or packet
        { out res[chan], base             ; stw tmp2, base[0] }

        // Receive address of packet buffer (re-use current buffer on error)
                                          // Store off the missing word that was used for runt detection
        { in base, res[chan]              ; stw tmp5, ptr[0] }

rx_next:
        //                                // Restore the ping-pong channel ID
        { nop                             ; ldw tmp1, sp[SP_PING_PONG] }

        // Must be a 32-bit instruction for long branch
        bu rx_sof

rx_error_too_long:
        { clrsr XS1_SR_IEBLE_SET(0, 1)    ; bu rx_wait_idle }

.align 16
rx_length_error:
rx_error_runt:
        // Increment the length error count
        { nop                             ; ldw tmp3, dp[mii_count_len_error] }
        //                                // Restore the ping-pong channel ID
        { add tmp3, tmp3, 1               ; ldw tmp1, sp[SP_PING_PONG] }
        { nop                             ; stw tmp3, dp[mii_count_len_error] }
        bu rx_sof

.align 16
rx_error_crc:
        // Increment the length error count
        { nop                             ; ldw tmp3, dp[mii_count_crc_error] }
        //                                // Restore the ping-pong channel ID
        { add tmp3, tmp3, 1               ; ldw tmp1, sp[SP_PING_PONG] }
        { nop                             ; stw tmp3, dp[mii_count_crc_error] }
        bu rx_sof

.align 16
rx_error:
        // Clear the error so that it can fire again (tmp3 contains RX_ERR)
        { in tmp2, res[tmp3]              ; bu rx_wait_idle }

.align 16
rx_wait_idle:
        // Error in packet, wait for DV (tmp5) to be low // Restore the ping-pong channel
        { in tmp2, res[tmp5]              ; ldw tmp1, sp[SP_PING_PONG] }

        // Signal to ping-pong thread that it can run
        { out res[tmp1], tmp1             ; bu rx_next }

        // Clear the data port
        { setc res[p_rxd], XS1_SETC_RUN_CLRBUF ; nop }

        .align 4
        .cc_bottom rgmii_rx_lld.function

#else
        .cc_top rgmii_rx_lld.function
        .set    rgmii_rx_lld.nstackwords,0
        .globl  rgmii_rx_lld.nstackwords
        .set    rgmii_rx_lld.maxcores,0
        .globl  rgmii_rx_lld.maxcores
        .set    rgmii_rx_lld.maxtimers,0
        .globl  rgmii_rx_lld.maxtimers
        .set    rgmii_rx_lld.maxchanends,0
        .globl  rgmii_rx_lld.maxchanends

        .globl  rgmii_rx_lld
        .align  4
        .type   rgmii_rx_lld,@function
rgmii_rx_lld:
        .cc_bottom rgmii_rx_lld.function
#endif

