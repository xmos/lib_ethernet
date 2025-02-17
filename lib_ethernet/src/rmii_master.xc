// Copyright 2024-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include "rmii_master.h"
#include <xs1.h>
#include <print.h>
#include <stdlib.h>
#include <syscall.h>
#include <xclib.h>
#include <hwtimer.h>
#include "string.h"
#include "xassert.h"
#include "mii_buffering.h"
#include "debug_print.h"
#include "default_ethernet_conf.h"
#include "mii_common_lld.h"
#include "string.h"
#include "check_ifg_wait.h"
#include "rmii_rx_pins_exit.h"
#include "shaper.h"


#define QUOTEAUX(x) #x
#define QUOTE(x) QUOTEAUX(x)

// As of the v12/13 xTIMEcomper tools. The compiler schedules code around a
// bit too much which violates the timing constraints. This change to the
// crc32 makes it a barrier to scheduling. This is not really
// recommended practice since it inhibits the compiler in a bit of a hacky way,
// but is perfectly safe.
#undef crc32
#define crc32(a, b, c) {__builtin_crc32(a, b, c); asm volatile (""::"r"(a):"memory");}

#ifndef MII_TX_TIMESTAMP_END_OF_PACKET
#define MII_TX_TIMESTAMP_END_OF_PACKET (0)
#endif

#define ETH_RX_4B_USE_ASM    1 // Use fast dual-issue ASM version of 4b Rx
#define ETH_RX_1B_USE_ASM    1 // Use fast dual-issue ASM version of 1b Rx

#define RECEIVE_PREAMBLE_WITH_SELECT_4b_ASM (1) // Call asm version of receive_full_preamble_4b_with_select
#define RECEIVE_PREAMBLE_WITH_SELECT_1b_ASM (1) // Call asm version of receive_full_preamble_1b_with_select


// After-init delay (used at the end of rmii_init)
#define PHY_INIT_DELAY 10000000

// The inter-frame gap is 96 bit times, which is 960 ns with one 1bit time being 10ns for RMII. 96 bit times = 960 ns = 96 reference timer ticks.
// This is the minimum time between one frame TX end and the next frame TX start (delay between TX_EN going low for the previous frame and TX_EN going high for the next frame).
// However, the EOF time stamp is taken when the CRC word goes into the
// transfer register, so there's a delay before the last bit of the CRC word is output on the wire, which is when TX_EN goes low.
// This delay is different for 4b and 1b TXD ports as described below.

// For 4b TXD port, 32 bits are output on the port, 4bits per 20ns RMII clock tick, so 8 ticks to output one 32 bit word.
// when tx_4b_word() for the CRC word returns, there's 7 ticks before the last word goes from the transfer register to shift register
// and another 8 ticks before the shift register is shifted out on the wire. So, a total of (7+8)*20ns = 300ns = 30 reference timer ticks
// between the tx_4b_word() for CRC word returning and the last bit shifted on the wire, which is when TX_EN goes low.

// For 1b TXD port, in a tx_1b_word() call 16 bits are output on the port, 1bit per 20ns RMII clock tick, so 16 ticks to output one 16 bit word, while
// in a tx_1b_byte() call 4 bits are output on the port, 1bit per 20ns RMII clock tick, so 4 ticks to output one byte.
//when tx_1b_word() for the CRC word returns, there's <N> ticks before the last word goes from the transfer register to shift register
// and another 16 ticks before the shift register is shifted out on the wire.
// N depends on what's in the shift register for the last but one (the one before CRC) transfer. If the last but one transfer is a word (tx_1b_word)
// which happens when there are no tail bytes in the frame, there's a delay of 15 ticks (16 - 1) before the last word moves from transfer to shift register,
// so N = 15.
// If the last but one transfer is a byte  (tx_1b_byte), there's a delay of 3 ticks (4 - 1) before the last word moves from transfer to shift register.
// which makes N = 3
// So the total delay between the tx_1b_word() for CRC word returning and the last bit shifted on the wire, which is when TX_EN goes low is
// (N + 16)*20ns.
// For frames with no tail this is (15+16)*20ns = 620ns = 62 reference timer ticks
// For frames with no tail bytes this is (3+16)*20ns = 380ns = 38 reference timer ticks

// So the RMII_ETHERNET_IFG_AS_REF_CLOCK_COUNT_4b is (96 + 30), and
// RMII_ETHERNET_IFG_AS_REF_CLOCK_COUNT_4b is (96 + 62) for frames with no tail bytes and (96 + 38) for frames with tail bytes.

// Further, there's an adjustment needed due to the fact that
// 1. The instruction that reads the timer is in fact the next instruction adter the out of the CRC word.
// 2. There's a delay between the timer wait for the next packet and the preamble actually showing up on the wire (TX_EN goes high when the first bit shows up)
//    This is the overhead of zip/unzip etc. before the first word is out on the TXD port.
// This adjustment is seen from the VCD trace as 120 ns for 1b TXD case and 80 ns for 4b TXD case, for a core frequency of 600MHz with 8 threads running.
// Note that this will vary depending on the processor speed.
// The defines, RMII_ETHERNET_IFG_DELAY_ADJUSTMENT_4b and RMII_ETHERNET_IFG_DELAY_ADJUSTMENT_1b are set to 12 and 8 reference timer ticks respectively.
// These are overridable defines and can be overriden if the processor is running faster than what these were measured for.

#ifndef RMII_ETHERNET_IFG_DELAY_ADJUSTMENT_4b
    #define RMII_ETHERNET_IFG_DELAY_ADJUSTMENT_4b (8) // In reference timer ticks
#endif

#ifndef RMII_ETHERNET_IFG_DELAY_ADJUSTMENT_1b
    #define RMII_ETHERNET_IFG_DELAY_ADJUSTMENT_1b (12) // In reference timer ticks
#endif

#define RMII_ETHERNET_IFG_AS_REF_CLOCK_COUNT_4b  (96 + 30 - RMII_ETHERNET_IFG_DELAY_ADJUSTMENT_4b)
#define RMII_ETHERNET_IFG_AS_REF_CLOCK_COUNT_1b_NO_TAIL_BYTES  (96 + 62 - RMII_ETHERNET_IFG_DELAY_ADJUSTMENT_1b)
#define RMII_ETHERNET_IFG_AS_REF_CLOCK_COUNT_1b_TAIL_BYTES  (96 + 38 - RMII_ETHERNET_IFG_DELAY_ADJUSTMENT_1b)


// Helpers to save a few cycles
#define SET_PORT_SHIFT_COUNT(p, sc) asm volatile("setpsc res[%0], %1" : : "r" (p), "r" (sc));
#define PORT_IN(p, ret) asm volatile("in %0, res[%1]" : "=r" (ret)  : "r" (p));
#define PORT_PART_IN_16(p, ret) asm volatile("inpw %0, res[%1], 16" : "=r"(ret) : "r" (p));



//////////////////// RMII PORT SETUP ////////////////////////

static void rmii_master_init_rx_common(in port p_clk,
                                       in port p_rxdv,
                                       clock rxclk,
                                       rmii_port_timing_t port_timing){
    // Enable data valid. Data ports already on and configured to 32b buffered.
    set_port_use_on(p_rxdv);

    // Init Rx capture clock block
    set_clock_on(rxclk);
    set_clock_src(rxclk, p_clk);        // Use ext clock

    // Connect to data valid and configure
    set_port_clock(p_rxdv, rxclk);      // Connect to clock block
    set_clock_ready_src(rxclk, p_rxdv); // Enable data valid

    set_clock_rise_delay(rxclk, port_timing.clk_delay_rx_rising);
    set_clock_fall_delay(rxclk, port_timing.clk_delay_rx_falling);
}


unsafe void rmii_master_init_rx_4b( in port p_clk,
                                    in buffered port:32 * unsafe rx_data,
                                    in port p_rxdv,
                                    clock rxclk,
                                    rmii_port_timing_t port_timing){
    rmii_master_init_rx_common(p_clk, p_rxdv, rxclk, port_timing);

    set_port_clock(*rx_data, rxclk); // Connect to rx clock block
    set_port_strobed(*rx_data);      // Strobed slave (only accept data when valid asserted)
    set_port_slave(*rx_data);

    clearbuf(*rx_data);

    start_clock(rxclk);
}

unsafe void rmii_master_init_rx_1b(in port p_clk,
                            in buffered port:32 * unsafe rx_data_0,
                            in buffered port:32 * unsafe rx_data_1,
                            in port p_rxdv,
                            clock rxclk,
                            rmii_port_timing_t port_timing){
    rmii_master_init_rx_common(p_clk, p_rxdv, rxclk, port_timing);

    set_port_clock(*rx_data_0, rxclk);  // Connect to rx clock block
    set_port_strobed(*rx_data_0);       // Strobed slave (only accept data when valid asserted)
    set_port_slave(*rx_data_0);

    set_port_clock(*rx_data_1, rxclk);  // Same for second data port
    set_port_strobed(*rx_data_1);
    set_port_slave(*rx_data_1);

    clearbuf(*rx_data_0);
    clearbuf(*rx_data_1);

    start_clock(rxclk);
}

static void rmii_master_init_tx_common( in port p_clk,
                                        out port p_txen,
                                        clock txclk,
                                        rmii_port_timing_t port_timing){
    // Enable tx enable valid signal. Data ports already on and configured to 32b buffered.
    set_port_use_on(p_txen);
    p_txen <: 0; // Ensure is initially low so no spurious enables

    // Init Tx transmit clock block and clock from clk input port
    set_clock_on(txclk);
    set_clock_src(txclk, p_clk);

    // Connect txen and configure as ready (valid) signal
    set_port_mode_ready(p_txen);
    set_port_clock(p_txen, txclk);

    set_clock_rise_delay(txclk, port_timing.clk_delay_tx_rising);
    set_clock_fall_delay(txclk, port_timing.clk_delay_tx_falling);
}


unsafe void rmii_master_init_tx_4b( in port p_clk,
                                    out buffered port:32 * unsafe tx_data,
                                    out port p_txen,
                                    clock txclk,
                                    rmii_port_timing_t port_timing){
    *tx_data <: 0;  // Ensure lines are low
    sync(*tx_data); // And wait to empty. This ensures no spurious p_txen on init

    rmii_master_init_tx_common(p_clk, p_txen, txclk, port_timing);

    // Configure so that tx_data controls the ready signal strobe
    set_port_strobed(*tx_data);
    set_port_master(*tx_data);
    set_port_ready_src(p_txen, *tx_data);
    set_port_clock(*tx_data, txclk);

    start_clock(txclk);
}

unsafe void rmii_master_init_tx_1b( in port p_clk,
                                    out buffered port:32 * unsafe tx_data_0,
                                    out buffered port:32 * unsafe tx_data_1,
                                    out port p_txen,
                                    clock txclk,
                                    rmii_port_timing_t port_timing){
    *tx_data_0 <: 0;  // Ensure lines are low
    sync(*tx_data_0); // And wait to empty. This ensures no spurious p_txen on init
    *tx_data_1 <: 0;
    sync(*tx_data_1);

    rmii_master_init_tx_common(p_clk, p_txen, txclk, port_timing);

    // Configure so that just tx_data_0 controls the read signal strobe
    // When we transmit we will ensure both port buffers are launched
    // at the same time so aligned
    set_port_strobed(*tx_data_0);
    set_port_master(*tx_data_0);
    set_port_ready_src(p_txen, *tx_data_0);

    // But we still want both ports connected to the tx clock block
    set_port_clock(*tx_data_0, txclk);
    set_port_clock(*tx_data_1, txclk);

    start_clock(txclk);
}

//////////////////////////////////////// RX ////////////////////////////////////
unsigned receive_full_preamble_4b_with_select_asm(in port p_mii_rxdv,
                                              in buffered port:32 p_mii_rxd,
                                              rmii_data_4b_pin_assignment_t rx_port_4b_pins);


unsigned receive_full_preamble_4b_with_select(in port p_mii_rxdv,
                                              in buffered port:32 p_mii_rxd,
                                              rmii_data_4b_pin_assignment_t rx_port_4b_pins)
{
    unsigned crc = 0x9226F562;
    unsigned word2, word1;
    int count = 0;
    const unsigned expected_preamble = 0xD5555555;

    p_mii_rxdv when pinseq(1) :> int;

    while(1) {
      select {
        case p_mii_rxd :> word2:
            if(count == 3)
            {
                uint64_t combined = (uint64_t)word1 | ((uint64_t)word2 << 32);
                {word2, word1} = unzip(combined, 1);
                if(rx_port_4b_pins == USE_LOWER_2B){
                    if(word1 != expected_preamble)
                    {
                        crc = ~crc;
                    }
                    return crc;
                } else {
                    if(word2 != expected_preamble)
                    {
                        crc = ~crc;
                    }
                    return crc;
                }

            }
            word1 = word2;
            count++;
            break;
        case p_mii_rxdv when pinseq(0) :> int:
            return 0;
            break;
      }
    }
    return 0;

}
static inline unsigned rx_word_4b(in buffered port:32 p_mii_rxd,
                                  rmii_data_4b_pin_assignment_t rx_port_4b_pins){
    unsigned word1, word2;
    p_mii_rxd :> word1;
    p_mii_rxd :> word2;
    uint64_t combined = (uint64_t)word1 | ((uint64_t)word2 << 32);
    // Reuse word1/2
    {word2, word1} = unzip(combined, 1);
    if(rx_port_4b_pins == USE_LOWER_2B){
        return word1;
    } else {
        return word2;
    }
}

// Prototype for ASM version of this main body
{int, unsigned, unsigned* unsafe} extern master_rx_pins_4b_body_asm(  unsigned * unsafe dptr,
                                                                        in port p_mii_rxdv,
                                                                        in buffered port:32 p_mii_rxd,
                                                                        rmii_data_4b_pin_assignment_t rx_port_4b_pins,
                                                                        unsigned * unsafe timestamp,
                                                                        unsigned * unsafe wrap_ptr,
                                                                        unsigned * unsafe write_end_ptr);

// XC version of main body. Kept for readibility and reference for ASM version
// {num_rx_bytes, crc, dptr}
{int, unsigned, unsigned* unsafe} master_rx_pins_4b_body( unsigned * unsafe dptr,
                                                            in port p_mii_rxdv,
                                                            in buffered port:32 p_mii_rxd,
                                                            rmii_data_4b_pin_assignment_t rx_port_4b_pins,
                                                            unsigned * unsafe timestamp,
                                                            unsigned * unsafe wrap_ptr,
                                                            unsigned * unsafe write_end_ptr){

    unsigned port_this, port_last; // Most recent and previous port read (32b = 2 data bytes)
    unsigned in_counter = 0; // We need two INs per word. Needed to track the tail handling.

    const unsigned poly = 0xEDB88320;

#if RECEIVE_PREAMBLE_WITH_SELECT_4b_ASM
    unsigned crc = receive_full_preamble_4b_with_select_asm(p_mii_rxdv, p_mii_rxd, rx_port_4b_pins);
#else
    unsigned crc = receive_full_preamble_4b_with_select(p_mii_rxdv, p_mii_rxd, rx_port_4b_pins);
#endif

    /* Timestamp the start of packet and record it in the packet structure */
    timer tmr;
    unsafe{ tmr :> *timestamp; }

    int num_rx_bytes = -4; // Subtract the CRC bytes

    // Consume frame one long word at a time
    while(1) {
        select {
            case p_mii_rxdv when pinseq(0) :> int:
                unsigned bits_left_in_port = endin(p_mii_rxd);
                if(!crc)
                {
                    unsigned port_residual;
                    PORT_IN(p_mii_rxd, port_residual);
                    num_rx_bytes = 0;
                }
                else
                {
                    uint64_t combined = 0;          // Bit pattern that we will reconstruct from tail pre-unzip
                    unsigned taillen_bytes = 0;     // Number of data bytes in tail 0..3
                    // in_counter will be set if 2 data bytes or more remaining in tail
                    // This logic works out which bit patterns from which port inputs need to be
                    // recombined to extract the tail using the unzip

                    if(bits_left_in_port) {
                        unsigned port_residual;
                        PORT_IN(p_mii_rxd, port_residual);
                        if(in_counter)
                        {
                            combined = ((uint64_t)port_last << 16) | ((uint64_t)port_residual << 32);
                            taillen_bytes = 3;
                        }
                        else{
                            combined = ((uint64_t)port_residual << 32);
                            taillen_bytes = 1;
                        }
                    }
                    else
                    {
                        if(in_counter)
                        {
                            combined = (uint64_t)port_last << 32;
                            taillen_bytes = 2;
                        }
                    }

                    num_rx_bytes += (taillen_bytes);

                    // Now turn the last constructed bit pattern into a word
                    unsigned upper, lower;
                    {upper, lower} = unzip(combined, 1);

                    // Now CRC remaining received bytes
                    if(taillen_bytes > 0){
                        // Make it right aligned as CRC operates on LSb first
                        unsigned tail;
                        if(rx_port_4b_pins == USE_LOWER_2B) {
                            tail = lower >> ((4 - taillen_bytes) << 3);
                        } else {
                            tail = upper >> ((4 - taillen_bytes) << 3);
                        }
                        crcn(crc, tail, poly, taillen_bytes << 3);
                    }

                }

                return {num_rx_bytes, crc, dptr};
                break;

            case p_mii_rxd :> port_this:
                if(in_counter) {
                    uint64_t combined = (uint64_t)port_last | ((uint64_t)port_this << 32);
                    {port_this, port_last} = unzip(combined, 1); // Reuse existing vars port_this, port_last  as upper, lower

                    // Only write to buffer if it hasn't hit the end of the writable space
                    if (dptr != write_end_ptr) {
                        if(rx_port_4b_pins == USE_LOWER_2B) unsafe{
                            *dptr = port_last; // lower
                            crc32(crc, port_last, poly);
                        } else unsafe {
                            *dptr = port_this; // upper
                            crc32(crc, port_this, poly);
                        }


                        dptr++;
                        /* The wrap pointer contains the address of the start of the buffer */
                        if (dptr == wrap_ptr) unsafe{
                            dptr = (unsigned * unsafe) *dptr;
                        }
                        num_rx_bytes += 4;
                    }
                } else {
                    // Just store for next time around or tail >= 2B
                    port_last = port_this;
                }

                in_counter ^= 1; // Efficient (++in_counter % 2)
                break;
        } // select
    } // While(1)
    return {0, 0, NULL};
}

unsafe void rmii_master_rx_pins_4b( mii_mempool_t rx_mem,
                                    mii_packet_queue_t incoming_packets,
                                    unsigned * unsafe rdptr,
                                    in port p_mii_rxdv,
                                    in buffered port:32 * unsafe p_mii_rxd,
                                    rmii_data_4b_pin_assignment_t rx_port_4b_pins,
                                    volatile int * unsafe running_flag_ptr,
                                    chanend c_rx_pins_exit){

    // Setup ISR to for exiting this task
    int isrstack[RXE_ISR_CONTEXT_WORDS] = {0};
    rx_end_isr_ctx_t isr_ctx = {
            isrstack,
            c_rx_pins_exit,
            p_mii_rxdv,
    };
    rx_end_install_isr(&isr_ctx);

    /* Pointers to data that needs the latest value being read */
    volatile unsigned * unsafe p_rdptr = (volatile unsigned * unsafe)rdptr;

    /* Set up the wrap markers for the two memory buffers. These are the points at which we must wrap data back to the beginning of the buffer */
    unsigned * unsafe wrap_ptr = mii_get_wrap_ptr(rx_mem);

    /* Make sure we do not start in the middle of a packet */
    p_mii_rxdv when pinseq(0) :> int lo;

    while (*running_flag_ptr) {
        /* Read the shared pointer where the read pointer is kept up to date by the management process (mii_ethernet_server_aux). */
        unsigned * unsafe rdptr = (unsigned * unsafe)*p_rdptr;

        /* Grab buffers to read the packet into. mii_reserve always returns a buffer we can use (though it may be a dummy buffer that gets thrown away later if we are out of buffer space). */
        unsigned * unsafe end_ptr;
        mii_packet_t * unsafe buf = mii_reserve(rx_mem, rdptr, &end_ptr);

        unsigned crc;
        unsigned * unsafe dptr = &buf->data[0];

        // For return values from next function
        int num_rx_bytes;
#if ETH_RX_4B_USE_ASM
        {num_rx_bytes, crc, dptr} = master_rx_pins_4b_body_asm(dptr,
                                                                                p_mii_rxdv,
                                                                                *p_mii_rxd,
                                                                                rx_port_4b_pins,
                                                                                (unsigned*)&buf->timestamp,
                                                                                wrap_ptr,
                                                                                end_ptr);
#else

        {num_rx_bytes, crc, dptr} = master_rx_pins_4b_body(dptr,
                                                                            p_mii_rxdv,
                                                                            *p_mii_rxd,
                                                                            rx_port_4b_pins,
                                                                            (unsigned*)&buf->timestamp,
                                                                            wrap_ptr,
                                                                            end_ptr);
#endif
        // Note: we don't store the last word since it contains the CRC and
        // we don't need it from this point on. Endin returns the number of bits of data in the port remaining.
        // Due to the nature of whole bytes in ethernet, each taking 16b of the register, this number will be 0 or 16

        // This is needed to prevent the next preamble read take in residual junk
        clearbuf(*p_mii_rxd);

        buf->length = num_rx_bytes;
        buf->crc = crc;


        /* Update where the write pointer is in memory */
        mii_commit(rx_mem, dptr);

        /* Record the fact that there is a valid packet ready for filtering */
        /*  - the assumption is that the filtering is running fast enough */
        /*    to keep up and process the packets so that the incoming_packet */
        /*    pointers never fill up */
        mii_add_packet(incoming_packets, buf);
    }
    
    // Exit cleanly so we don't leave channels full/in use
    rx_end_disable_interrupt();
    rx_end_drain_and_clear(c_rx_pins_exit);
}

static inline unsigned rx_1b_word(in buffered port:32 p_mii_rxd_0,
                                  in buffered port:32 p_mii_rxd_1){

    unsigned word, word2;

    // We need to set this so it puts the shift reg in the transfer reg after 16.
    set_port_shift_count(p_mii_rxd_0, 16);
    set_port_shift_count(p_mii_rxd_1, 16);

    // Use full XC IN which also does SETC 0x0001. We have plenty of time at preamble.
    p_mii_rxd_0 :> word;
    p_mii_rxd_1 :> word2;

    // Zip together. Note we care about the upper 16b of the port only (newest data).
    uint64_t combined = zip(word2, word, 0);
    // resuse word
    word = (uint32_t) (combined >> 32); // Discard lower word - two port upper 16b combine to upper 32b zipped.

    return word;
}

unsigned receive_full_preamble_1b_with_select_asm(in buffered port:32 p_mii_rxd_0,
                                                    in buffered port:32 p_mii_rxd_1,
                                                    in port p_mii_rxdv);



unsigned receive_full_preamble_1b_with_select(in buffered port:32 p_mii_rxd_0,
                                              in buffered port:32 p_mii_rxd_1,
                                              in port p_mii_rxdv)
{
    unsigned crc = 0x9226F562;
    unsigned word, word2;

    p_mii_rxdv when pinseq(1) :> int;

    while(1) {
      select {
        case p_mii_rxd_0 :> word:
            p_mii_rxd_1 :> word2;

            const unsigned expected_preamble = 0xD5555555;

            uint64_t combined = zip(word2, word, 0);
            unsigned sfd_preamble = (uint32_t) (combined >> 32); // Discard lower word - two port upper 16b combine to upper 32b zipped.
            if(sfd_preamble != expected_preamble) {
                // Corrupt the CRC so that the packet is discarded
                crc = ~crc;
            }
            return crc;

          break;
        case p_mii_rxdv when pinseq(0) :> int:
            return 0;
            break;
      }
    }
    return 0;
}

// Brining this out to an inline while(1) select improves performance as compiler can hoist select setup
{unsigned* unsafe, unsigned, unsigned}  master_rx_pins_1b_body( unsigned * unsafe dptr,
                                                                in port p_mii_rxdv,
                                                                in buffered port:32 p_mii_rxd_0,
                                                                in buffered port:32 p_mii_rxd_1,
                                                                unsigned * unsafe timestamp,
                                                                unsigned * unsafe wrap_ptr,
                                                                unsigned * unsafe end_ptr
                                                                ){
unsafe{
    const unsigned poly = 0xEDB88320;
    // Discount the CRC word
    int num_rx_bytes = -4;

    // Receive second half of preamble and check
#if RECEIVE_PREAMBLE_WITH_SELECT_1b_ASM
    unsigned crc = receive_full_preamble_1b_with_select_asm(p_mii_rxd_0, p_mii_rxd_1, p_mii_rxdv);
#else
    unsigned crc = receive_full_preamble_1b_with_select(p_mii_rxd_0, p_mii_rxd_1, p_mii_rxdv);
#endif

    // Timestamp the start of packet and record it in the packet structure
    timer tmr;
    tmr :> *timestamp;

    unsigned word;

    // This clears after each IN so setup again
    set_port_shift_count(p_mii_rxd_0, 16);
    set_port_shift_count(p_mii_rxd_1, 16);


    while(1) {
        select {
            case p_mii_rxdv when pinseq(0) :> int:
                // This tells us how many bits left in the port shift register and moves the shift register contents
                // to the trafsnfer register. The number of bits will both be the same (ports are synched) so discard one.
                // Bits will either be 4, 8 or 12 (x2 as two ports) representing a tail of 1, 2 or 3 bytes

                unsigned remaining_bits_in_port = endin(p_mii_rxd_0);
                endin(p_mii_rxd_1);

                if(remaining_bits_in_port > 0){
                    unsigned word, word2;
                    // Grab the transfer registers
                    PORT_IN(p_mii_rxd_0, word); // Saves one instruction over :>
                    PORT_IN(p_mii_rxd_1, word2); // Saves one instruction over :>

                    uint64_t combined = zip(word2, word, 0);
                    word = (uint32_t)(combined >> 32);

                    // Shift away unwanted part of word
                    unsigned tail = word >> (32 - (remaining_bits_in_port << 1));
                    crcn(crc, tail, poly, remaining_bits_in_port << 1);

                    unsigned taillen_bytes = remaining_bits_in_port >> 2; // Divide by 4 because we get 4b on each port for a data byte
                    num_rx_bytes += taillen_bytes;
                }

                return {dptr, crc, num_rx_bytes};
                break;

            case p_mii_rxd_0 :> word:
                unsigned word2;
                PORT_IN(p_mii_rxd_1, word2); // Saves one instruction.
                uint64_t combined = zip(word2, word, 0);
                word = (uint32_t)(combined >> 32);

                crc32(crc, word, poly);

                /* Prevent the overwriting of packets in the buffer. If the end_ptr is reached
                * then this packet will be dropped as there is not enough room in the buffer. */
                if (dptr != end_ptr) {
                    *dptr = word;
                    dptr++;
                    num_rx_bytes += 4;
                    /* The wrap pointer contains the address of the start of the buffer */
                    if (dptr == wrap_ptr)
                        dptr = (unsigned * unsafe) *dptr;
                }

                // Reset shift count since it gets cleared after each IN
                set_port_shift_count(p_mii_rxd_0, 16);
                set_port_shift_count(p_mii_rxd_1, 16);
                break;
        }
    }
    // Unreachable but keep compiler happy
    return {NULL, 0, 0};
}
} // unsafe


// Prototype of the asm version of this function
{unsigned* unsafe, unsigned, unsigned}  extern master_rx_pins_1b_body_asm( unsigned * unsafe dptr,
                                                                in port p_mii_rxdv,
                                                                in buffered port:32 p_mii_rxd_0,
                                                                in buffered port:32 p_mii_rxd_1,
                                                                unsigned * unsafe timestamp,
                                                                unsigned * unsafe wrap_ptr,
                                                                unsigned * unsafe end_ptr
                                                                );

unsafe void rmii_master_rx_pins_1b( mii_mempool_t rx_mem,
                                    mii_packet_queue_t incoming_packets,
                                    unsigned * unsafe rdptr,
                                    in port p_mii_rxdv,
                                    in buffered port:32 * unsafe p_mii_rxd_0,
                                    in buffered port:32 * unsafe p_mii_rxd_1,
                                    volatile int * unsafe running_flag_ptr,
                                    chanend c_rx_pins_exit){
    
    // Setup ISR to for exiting this task
    int isrstack[RXE_ISR_CONTEXT_WORDS] = {0};
    rx_end_isr_ctx_t isr_ctx = {
            isrstack,
            c_rx_pins_exit,
            p_mii_rxdv,
    };
    rx_end_install_isr(&isr_ctx);


    /* Pointers to data that needs the latest value being read */
    volatile unsigned * unsafe p_rdptr = (volatile unsigned * unsafe)rdptr;

    /* Set up the wrap markers for the two memory buffers. These are the points at which we must wrap data back to the beginning of the buffer */
    unsigned * unsafe wrap_ptr = mii_get_wrap_ptr(rx_mem);

    /* Make sure we do not start in the middle of a packet */
    p_mii_rxdv when pinseq(0) :> int lo;

    while (*running_flag_ptr) {
        /* Read the shared pointer where the read pointer is kept up to date by the management process (mii_ethernet_server_aux). */
        unsigned * unsafe rdptr = (unsigned * unsafe)*p_rdptr;

        /* Grab buffers to read the packet into. mii_reserve always returns a buffer we can use (though it may be a dummy buffer that gets thrown away later if we are out of buffer space). */
        unsigned * unsafe end_ptr;
        mii_packet_t * unsafe buf = mii_reserve(rx_mem, rdptr, &end_ptr);

        unsigned poly = 0xEDB88320;
        unsigned * unsafe dptr = &buf->data[0];

        // Receive first half of preamble and discard

        unsigned crc;
        // Receive body of frame. This is in a separate function to allow more efficient select.
        int num_rx_bytes;

#if ETH_RX_1B_USE_ASM
        {dptr, crc, num_rx_bytes} = master_rx_pins_1b_body_asm(dptr, p_mii_rxdv, *p_mii_rxd_0, *p_mii_rxd_1, (unsigned*)&buf->timestamp, wrap_ptr, end_ptr);
#else
        {dptr, crc, num_rx_bytes} = master_rx_pins_1b_body(dptr, p_mii_rxdv, *p_mii_rxd_0, *p_mii_rxd_1, (unsigned*)&buf->timestamp, wrap_ptr, end_ptr);
#endif

        // This is needed to prevent the next preamble read take in residual junk
        clearbuf(*p_mii_rxd_0);
        clearbuf(*p_mii_rxd_1);

        buf->length = num_rx_bytes;
        buf->crc = crc;

        if (dptr != end_ptr) {
            /* Update where the write pointer is in memory */
            mii_commit(rx_mem, dptr);

            /* Record the fact that there is a valid packet ready for filtering */
            /*  - the assumption is that the filtering is running fast enough */
            /*    to keep up and process the packets so that the incoming_packet */
            /*    pointers never fill up */
            mii_add_packet(incoming_packets, buf);
        }
    } // while running

    // Exit cleanly so we don't leave channels full/in use
    rx_end_disable_interrupt();
    rx_end_drain_and_clear(c_rx_pins_exit);
}

///////////////////////////////////// TX /////////////////////////////////////////
static inline void tx_4b_word(out buffered port:32 p_mii_txd,
                              unsigned word,
                              rmii_data_4b_pin_assignment_t tx_port_4b_pins){
    uint64_t zipped;
    if(tx_port_4b_pins == USE_LOWER_2B){
        zipped = zip(0, word, 1);
    } else {
        zipped = zip(word, 0, 1);
    }
    p_mii_txd <: zipped & 0xffffffff;
    p_mii_txd <: zipped >> 32;
}


static inline void tx_4b_byte(out buffered port:32 p_mii_txd,
                              unsigned word,
                              rmii_data_4b_pin_assignment_t tx_port_4b_pins){
    uint64_t zipped;
    if(tx_port_4b_pins == USE_LOWER_2B){
        zipped = zip(0, word, 1);
    } else {
        zipped = zip(word, 0, 1);
    }
    partout(p_mii_txd, 16, zipped & 0xffffffff);
}


unsafe unsigned rmii_transmit_packet_4b(mii_mempool_t tx_mem,
                                    mii_packet_t * unsafe buf,
                                    out buffered port:32 p_mii_txd,
                                    rmii_data_4b_pin_assignment_t tx_port_4b_pins,
                                    hwtimer_t ifg_tmr,
                                    unsigned &ifg_time,
                                    unsigned last_frame_end_time)
{
    unsigned time;
    register const unsigned poly = 0xEDB88320;
    unsigned int crc = 0;
    unsigned * unsafe dptr;
    int i=0;
    int word_count = buf->length >> 2;
    int tail_byte_count = buf->length & 3;
    unsigned * unsafe wrap_ptr;
    dptr = &buf->data[0];
    wrap_ptr = mii_get_wrap_ptr(tx_mem);

    // Check that we are out of the inter-frame gap
    unsigned now;
    ifg_tmr :> now;
    unsigned wait = check_if_ifg_wait_required(last_frame_end_time, ifg_time, now);
    if(wait)
    {
        ifg_tmr when timerafter(ifg_time) :> ifg_time;
    }

    tx_4b_word(p_mii_txd, 0x55555555, tx_port_4b_pins);
    tx_4b_word(p_mii_txd, 0xD5555555, tx_port_4b_pins);

    if (!MII_TX_TIMESTAMP_END_OF_PACKET && buf->timestamp_id) {
        ifg_tmr :> time;
    }

    unsigned word = *dptr;
    tx_4b_word(p_mii_txd, word, tx_port_4b_pins);
    dptr++;
    i++;
    crc32(crc, ~word, poly);

    do {
        unsigned word = *dptr;
        dptr++;
        if (dptr == wrap_ptr) {
            dptr = (unsigned *) *dptr;
        }
        i++;
        crc32(crc, word, poly);
        tx_4b_word(p_mii_txd, word, tx_port_4b_pins);
    } while (i < word_count);

    if (MII_TX_TIMESTAMP_END_OF_PACKET && buf->timestamp_id) {
        ifg_tmr :> time;
    }

    if (tail_byte_count) {
        unsigned word = *dptr;
        switch (tail_byte_count) {
            default:
                __builtin_unreachable();
                break;
#pragma fallthrough
            case 3:
                tx_4b_byte(p_mii_txd, word, tx_port_4b_pins);
                word = crc8shr(crc, word, poly);
#pragma fallthrough
            case 2:
                tx_4b_byte(p_mii_txd, word, tx_port_4b_pins);
                word = crc8shr(crc, word, poly);
            case 1:
                tx_4b_byte(p_mii_txd, word, tx_port_4b_pins);
                crc8shr(crc, word, poly);
                break;
        }
    }
    crc32(crc, ~0, poly);
    tx_4b_word(p_mii_txd, crc, tx_port_4b_pins);
    ifg_tmr :> ifg_time;

    return time;
}


static inline void tx_1b_word(out buffered port:32 p_mii_txd_0,
                              out buffered port:32 p_mii_txd_1,
                              unsigned word){
    uint64_t combined = (uint64_t)word;
    uint32_t p0_val, p1_val;
    {p1_val, p0_val} = unzip(combined, 0);

    partout(p_mii_txd_1, 16, p1_val);
    partout(p_mii_txd_0, 16, p0_val);
}


static inline void tx_1b_byte(out buffered port:32 p_mii_txd_0,
                              out buffered port:32 p_mii_txd_1,
                              unsigned word){
    uint64_t combined = (uint64_t)word;
    uint32_t p0_val, p1_val;
    {p1_val, p0_val} = unzip(combined, 0);

    partout(p_mii_txd_0, 4, p0_val);
    partout(p_mii_txd_1, 4, p1_val);
}


unsafe unsigned rmii_transmit_packet_1b(mii_mempool_t tx_mem,
                                    mii_packet_t * unsafe buf,
                                    out buffered port:32 p_mii_txd_0,
                                    out buffered port:32 p_mii_txd_1,
                                    clock txclk,
                                    hwtimer_t ifg_tmr,
                                    unsigned &ifg_time,
                                    unsigned last_frame_end_time)
{
    unsigned time;
    register const unsigned poly = 0xEDB88320;
    unsigned int crc = 0;
    unsigned * unsafe dptr;
    int i=0;
    int word_count = buf->length >> 2;
    int tail_byte_count = buf->length & 3;
    unsigned * unsafe wrap_ptr;
    dptr = &buf->data[0];
    wrap_ptr = mii_get_wrap_ptr(tx_mem);

    // Check that we are out of the inter-frame gap
    unsigned now;
    ifg_tmr :> now;
    unsigned wait = check_if_ifg_wait_required(last_frame_end_time, ifg_time, now);
    if(wait)
    {
        ifg_tmr when timerafter(ifg_time) :> ifg_time;
    }

    // Ensure first Tx is synchronised so they launch at the same time. We will continue filling the buffer until the end of packet.
    stop_clock(txclk);
    tx_1b_word(p_mii_txd_0, p_mii_txd_1, 0x55555555);
    start_clock(txclk);
    tx_1b_word(p_mii_txd_0, p_mii_txd_1, 0xD5555555);

    if (!MII_TX_TIMESTAMP_END_OF_PACKET && buf->timestamp_id) {
        ifg_tmr :> time;
    }

    unsigned word = *dptr;
    tx_1b_word(p_mii_txd_0, p_mii_txd_1, word);
    dptr++;
    i++;
    crc32(crc, ~word, poly);

    do {
        unsigned word = *dptr;
        dptr++;
        if (dptr == wrap_ptr) {
            dptr = (unsigned *) *dptr;
        }
        i++;
        crc32(crc, word, poly);
        tx_1b_word(p_mii_txd_0, p_mii_txd_1, word);
    } while (i < word_count);

    if (MII_TX_TIMESTAMP_END_OF_PACKET && buf->timestamp_id) {
        ifg_tmr :> time;
    }

    if (tail_byte_count) {
        unsigned word = *dptr;
        switch (tail_byte_count) {
            default:
                __builtin_unreachable();
                break;
#pragma fallthrough
            case 3:
                tx_1b_byte(p_mii_txd_0, p_mii_txd_1, word);
                word = crc8shr(crc, word, poly);
#pragma fallthrough
            case 2:
                tx_1b_byte(p_mii_txd_0, p_mii_txd_1, word);
                word = crc8shr(crc, word, poly);
            case 1:
                tx_1b_byte(p_mii_txd_0, p_mii_txd_1, word);
                crc8shr(crc, word, poly);
                break;
        }
    }
    crc32(crc, ~0, poly);

    tx_1b_word(p_mii_txd_0, p_mii_txd_1, crc);

    ifg_tmr :> ifg_time;

    return time;
}



unsafe void rmii_master_tx_pins(mii_mempool_t tx_mem_lp,
                                mii_mempool_t tx_mem_hp,
                                mii_packet_queue_t packets_lp,
                                mii_packet_queue_t packets_hp,
                                mii_ts_queue_t ts_queue_lp,
                                unsigned tx_port_width,
                                out buffered port:32 * unsafe p_mii_txd_0,
                                out buffered port:32 * unsafe  p_mii_txd_1,
                                rmii_data_4b_pin_assignment_t tx_port_4b_pins,
                                clock txclk,
                                volatile ethernet_port_state_t * unsafe p_port_state,
                                volatile int * unsafe running_flag_ptr){

    // Flag for readability and faster comparison
    const unsigned use_4b = (tx_port_width == 4);

    // Need one timer to be able to read at any time for the shaper
    timer credit_tmr;
    // And a second timer to be enforcing the IFG gap
    hwtimer_t ifg_tmr;
    unsigned ifg_time = 0;
    unsigned eof_time = 0;

    qav_state_t qav_state = {0, 0, 0}; // Set times and credit to zero so it can tx first frame
    unsigned enable_shaper = p_port_state->qav_shaper_enabled;

    if (!ETHERNET_SUPPORT_TRAFFIC_SHAPER) {
        enable_shaper = 0;
    }
    if (ETHERNET_SUPPORT_HP_QUEUES && enable_shaper) {
        credit_tmr :> qav_state.current_time;
        qav_state.prev_time = qav_state.current_time;
    }

    ifg_tmr :> ifg_time;

    while (*running_flag_ptr) {
        mii_packet_t * unsafe buf = null;
        mii_ts_queue_t *p_ts_queue = null;
        mii_mempool_t tx_mem = tx_mem_hp;

        if (ETHERNET_SUPPORT_HP_QUEUES){
            buf = mii_get_next_buf(packets_hp);
        }

        if (enable_shaper) {
            credit_tmr :> qav_state.current_time;
            buf = shaper_do_idle_slope(buf, &qav_state, p_port_state);
        }

        if (!buf) {
            buf = mii_get_next_buf(packets_lp);
            p_ts_queue = &ts_queue_lp;
            tx_mem = tx_mem_lp;
        }

        if (!buf) {
            continue;
        }


        unsigned time;
        if(use_4b) {
            time = rmii_transmit_packet_4b(tx_mem, buf, *p_mii_txd_0, tx_port_4b_pins, ifg_tmr, ifg_time, eof_time);
            eof_time = ifg_time;
            ifg_time += RMII_ETHERNET_IFG_AS_REF_CLOCK_COUNT_4b;
        } else {
            time = rmii_transmit_packet_1b(tx_mem, buf, *p_mii_txd_0, *p_mii_txd_1, txclk, ifg_tmr, ifg_time, eof_time);
            eof_time = ifg_time;
            if((buf->length & 0x3))
            {
                ifg_time += RMII_ETHERNET_IFG_AS_REF_CLOCK_COUNT_1b_TAIL_BYTES;
            }
            else
            {
                ifg_time += RMII_ETHERNET_IFG_AS_REF_CLOCK_COUNT_1b_NO_TAIL_BYTES;
            }
        }



        const int packet_is_high_priority = (p_ts_queue == null);
        if (enable_shaper && packet_is_high_priority) {
            shaper_do_send_slope(buf->length, &qav_state);
        }

        if (mii_get_and_dec_transmit_count(buf) == 0) {
            /* The timestamp queue is only set for low-priority packets */
            if (!packet_is_high_priority) {
                if (buf->timestamp_id) {
                    mii_ts_queue_add_entry(*p_ts_queue, buf->timestamp_id, time);
                }

                mii_free_current(packets_lp);
            } else {
                mii_free_current(packets_hp);
            }
        }
    }
}
