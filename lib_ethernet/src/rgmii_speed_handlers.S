// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include "xs1.h"

.section .dp.data, "awd", @progbits

.cc_top notification_channel_ids.globl
.globl notification_channel_ids
notification_channel_ids:
.word 0, 0, 0, 0, 0, 0, 0

saved_word0:
.word 0
saved_word1:
.word 0
saved_word2:
.word 0
saved_word3:
.word 0
.cc_bottom notification_channel_ids.globl

.text
#if defined(__XS2A__)
        .cc_top log_speed_change_pointers.function
        .set    log_speed_change_pointers.nstackwords,0
        .globl  log_speed_change_pointers.nstackwords
        .set    log_speed_change_pointers.maxcores,1
        .globl  log_speed_change_pointers.maxcores
        .set    log_speed_change_pointers.maxtimers,0
        .globl  log_speed_change_pointers.maxtimers
        .set    log_speed_change_pointers.maxchanends,8
        .globl  log_speed_change_pointers.maxchanends

        .globl  log_speed_change_pointers
        .align  4
        .type   log_speed_change_pointers,@function
        .issue_mode single

log_speed_change_pointers:
        ENTSP_lu6 0

        ldaw r11, dp[notification_channel_ids]
        getr r1, XS1_RES_TYPE_CHANEND
        setd res[r1], r1
        stw r1, r11[0]
        stw r1, r0[0]
        getr r1, XS1_RES_TYPE_CHANEND
        setd res[r1], r1
        stw r1, r11[1]
        stw r1, r0[1]
        getr r1, XS1_RES_TYPE_CHANEND
        setd res[r1], r1
        stw r1, r11[2]
        stw r1, r0[2]
        getr r1, XS1_RES_TYPE_CHANEND
        setd res[r1], r1
        stw r1, r11[3]
        stw r1, r0[3]
        getr r1, XS1_RES_TYPE_CHANEND
        setd res[r1], r1
        stw r1, r11[4]
        stw r1, r0[4]
        getr r1, XS1_RES_TYPE_CHANEND
        setd res[r1], r1
        stw r1, r11[5]
        stw r1, r0[5]

        retsp 0

        .align 4
        .cc_bottom log_speed_change_pointers.function

#else // Not __XS2A__

        .cc_top log_speed_change_pointers.function
        .set    log_speed_change_pointers.nstackwords,0
        .globl  log_speed_change_pointers.nstackwords
        .set    log_speed_change_pointers.maxcores,0
        .globl  log_speed_change_pointers.maxcores
        .set    log_speed_change_pointers.maxtimers,0
        .globl  log_speed_change_pointers.maxtimers
        .set    log_speed_change_pointers.maxchanends,0
        .globl  log_speed_change_pointers.maxchanends

        .globl  log_speed_change_pointers
        .align  4
        .type   log_speed_change_pointers,@function
log_speed_change_pointers:
        .cc_bottom log_speed_change_pointers.function

#endif // __XS2A__

