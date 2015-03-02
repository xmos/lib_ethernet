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
        entsp 0

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
        getr r1, XS1_RES_TYPE_CHANEND
        setd res[r1], r1
        stw r1, r11[6]
        stw r1, r0[6]

        retsp 0

        .align 4
        .cc_bottom log_speed_change_pointers.function



        .cc_top install_speed_change_handler.function
        .set    install_speed_change_handler.nstackwords,0
        .globl  install_speed_change_handler.nstackwords
        .set    install_speed_change_handler.maxcores,1
        .globl  install_speed_change_handler.maxcores
        .set    install_speed_change_handler.maxtimers,0
        .globl  install_speed_change_handler.maxtimers
        .set    install_speed_change_handler.maxchanends,0
        .globl  install_speed_change_handler.maxchanends

        .globl  install_speed_change_handler
        .align  4
        .type   install_speed_change_handler,@function

install_speed_change_handler:
        entsp 0

        in r11, res[r0] // empty transfer register
        in r11, res[r0] // empty shift register

        // Set up the handler for when the mode changes
        ldap r11, speed_change_handler
        setv res[r0], r11
        setc res[r0], XS1_SETC_IE_MODE_INTERRUPT
        setd res[r0], r1
        setc res[r0], XS1_SETC_COND_NEQ
        eeu res[r0]

        // Enable interrupts on this core
        setsr XS1_SR_IEBLE_SET(0, 1)

        retsp 0

        .align 4
        .cc_bottom install_speed_change_handler.function



        .cc_top speed_change_handler.function
        .set    speed_change_handler.nstackwords,4
        .globl  speed_change_handler.nstackwords
        .set    speed_change_handler.maxcores,1
        .globl  speed_change_handler.maxcores
        .set    speed_change_handler.maxtimers,0
        .globl  speed_change_handler.maxtimers
        .set    speed_change_handler.maxchanends,0
        .globl  speed_change_handler.maxchanends

        .globl  speed_change_handler
        .align  4
        .type   speed_change_handler,@function

speed_change_handler:
        stw r0, dp[saved_word0]
        stw r1, dp[saved_word1]
        stw r2, dp[saved_word2]
        stw r11, dp[saved_word3]

        ldc r1, 0

        ldaw r11, dp[notification_channel_ids]
        ldw r0, r11[0]
        out res[r0], r1
        ldw r0, r11[1]
        out res[r0], r1
        ldw r0, r11[2]
        out res[r0], r1
        ldw r0, r11[3]
        out res[r0], r1
        ldw r0, r11[4]
        out res[r0], r1
        ldw r0, r11[5]
        out res[r0], r1
        ldw r0, r11[6]
        out res[r0], r1

        // GET resource ID and disable interrupt on it
        get r11, ed
        edu res[r11]

        ldw r11, dp[saved_word3]
        ldw r2, dp[saved_word2]
        ldw r1, dp[saved_word1]
        ldw r0, dp[saved_word0]
        kret

        .align 4
        .cc_bottom speed_change_handler.function

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


        .cc_top install_speed_change_handler.function
        .set    install_speed_change_handler.nstackwords,0
        .globl  install_speed_change_handler.nstackwords
        .set    install_speed_change_handler.maxcores,0
        .globl  install_speed_change_handler.maxcores
        .set    install_speed_change_handler.maxtimers,0
        .globl  install_speed_change_handler.maxtimers
        .set    install_speed_change_handler.maxchanends,0
        .globl  install_speed_change_handler.maxchanends

        .globl  install_speed_change_handler
        .align  4
        .type   install_speed_change_handler,@function
install_speed_change_handler:
        .cc_bottom install_speed_change_handler.function

#endif // __XS2A__

