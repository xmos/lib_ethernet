// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include "rmii_master.h"
#include <xs1.h>
#include <print.h>
#include <stdlib.h>
#include <syscall.h>
#include <xclib.h>
#include <hwtimer.h>
#include "mii_buffering.h"
#include "debug_print.h"
#include "default_ethernet_conf.h"
#include "mii_common_lld.h"
#include "string.h"

#define QUOTEAUX(x) #x
#define QUOTE(x) QUOTEAUX(x)

// As of the v12/13 xTIMEcomper tools. The compiler schedules code around a
// bit too much which violates the timing constraints. This change to the
// crc32 makes it a barrier to scheduling. This is not really
// recommended practice since it inhibits the compiler in a bit of a hacky way,
// but is perfectly safe.
#undef crc32
#define crc32(a, b, c) {__builtin_crc32(a, b, c); asm volatile (""::"r"(a):"memory");}


// Timing tuning constants
// TODO THESE NEED SETTING UP
#define PAD_DELAY_RECEIVE    0
#define PAD_DELAY_TRANSMIT   0
#define CLK_DELAY_RECEIVE    0
#define CLK_DELAY_TRANSMIT   0

// After-init delay (used at the end of rmii_init)
#define PHY_INIT_DELAY 10000000

// The inter-frame gap is 96 bit times (1 clock tick at 100Mb/s). However,
// the EOF time stamp is taken when the last but one word goes into the
// transfer register, so that leaves 96 bits of data still to be sent
// on the wire (shift register word, transfer register word, crc word).
// In the case of a non word-aligned transfer compensation is made for
// that in the code at runtime.
// The adjustment is due to the fact that the instruction
// that reads the timer is the next instruction after the out at the
// end of the packet and the timer wait is an instruction before the
// out of the pre-amble
#define MII_ETHERNET_IFS_AS_REF_CLOCK_COUNT  (96 + 96 - 9)


//////////////////// RMII PORT SETUP ////////////////////////

static void rmii_master_init_rx_common(in port p_clk,
                                       in port p_rxdv,
                                       clock rxclk){
    // Enable data valid. Data ports already on and configured to 32b buffered.
    set_port_use_on(p_rxdv);

    // Init Rx capture clock block
    set_clock_on(rxclk);
    set_clock_src(rxclk, p_clk);        // Use ext clock

    // Connect to data valid and configure 
    set_port_clock(p_rxdv, rxclk);      // Connect to clock block
    set_clock_ready_src(rxclk, p_rxdv); // Enable data valid

    set_clock_rise_delay(rxclk, CLK_DELAY_RECEIVE);
    set_clock_fall_delay(rxclk, CLK_DELAY_RECEIVE);
}


unsafe void rmii_master_init_rx_4b(in port p_clk,
                            in buffered port:32 * unsafe rx_data,
                            in port p_rxdv,
                            clock rxclk){
    rmii_master_init_rx_common(p_clk, p_rxdv, rxclk);

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
                            clock rxclk){
    rmii_master_init_rx_common(p_clk, p_rxdv, rxclk);

    set_port_clock(*rx_data_0, rxclk);  // Connect to rx clock block
    set_port_strobed(*rx_data_0);       // Strobed slave (only accept data when valid asserted)
    set_port_slave(*rx_data_0);

    set_port_clock(*rx_data_1, rxclk);
    set_port_strobed(*rx_data_1);
    set_port_slave(*rx_data_1);

    clearbuf(*rx_data_0);
    clearbuf(*rx_data_1);

    start_clock(rxclk);
}

static void rmii_master_init_tx_common( in port p_clk,
                                        out port p_txen,
                                        clock txclk){
    // Enable tx enable valid signal. Data ports already on and configured to 32b buffered.
    set_port_use_on(p_txen);

    // Init Tx transmit clock block and clock from clk input port
    set_clock_on(txclk);
    set_clock_src(txclk, p_clk);

    // Connect txen and configure as ready (valid) signal 
    set_port_clock(p_txen, txclk);
    set_port_mode_ready(p_txen);
    
    set_clock_rise_delay(txclk, CLK_DELAY_TRANSMIT);
    set_clock_rise_delay(txclk, CLK_DELAY_TRANSMIT);
}


unsafe void rmii_master_init_tx_4b( in port p_clk,
                                    out buffered port:32 * unsafe tx_data,
                                    out port p_txen,
                                    clock txclk){
    rmii_master_init_tx_common(p_clk, p_txen, txclk);

    clearbuf(*tx_data);

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
                                    clock txclk){
    rmii_master_init_tx_common(p_clk, p_txen, txclk);

    clearbuf(*tx_data_0);
    clearbuf(*tx_data_1);

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

//////////////////////// RX ///////////////////////////


#define MASTER_RX_CHUNK_HEAD \
    timer tmr; \
                \
    unsigned kernel_stack[MII_COMMON_HANDLER_STACK_WORDS]; \
    /* Pointers to data that needs the latest value being read */ \
    volatile unsigned * unsafe error_ptr = mii_setup_error_port(p_mii_rxer, p_mii_rxdv, kernel_stack); \
    volatile unsigned * unsafe p_rdptr = (volatile unsigned * unsafe)rdptr; \
                                                                            \
    /* Set up the wrap markers for the two memory buffers. These are the points at which we must wrap data back to the beginning of the buffer */ \
    unsigned * unsafe wrap_ptr = mii_get_wrap_ptr(rx_mem); \
                                                            \
    /* Make sure we do not start in the middle of a packet */ \
    p_mii_rxdv when pinseq(0) :> int lo; \
                                        \
    while (1) { \
        /* Discount the CRC word */ \
        int num_rx_bytes = -4; \
                                \
        /* Read the shared pointer where the read pointer is kept up to date by the management process (mii_ethernet_server_aux). */ \
        unsigned * unsafe rdptr = (unsigned * unsafe)*p_rdptr; \
                                                                \
        /* Grab buffers to read the packet into. mii_reserve always returns a buffer we can use (though it may be a dummy buffer that gets thrown away later if we are out of buffer space). */ \
        unsigned * unsafe end_ptr; \
        mii_packet_t * unsafe buf = mii_reserve(rx_mem, rdptr, &end_ptr); \
                                                                           \
        unsigned crc = 0x9226F562; \
        unsigned poly = 0xEDB88320; \
        unsigned * unsafe dptr = &buf->data[0]; \
                                                 \
        /* Enable interrupts as the rx_err port is configured to raise an interrupt that logs the error and continues. */ \
        asm("setsr 0x2"); \
                           \
        /* Wait for the start of the packet and timestamp it */ \
        unsigned sfd_preamble;
// END OF MASTER_RX_CHUNK_HEAD


#define MASTER_RX_CHUNK_TAIL \
        unsigned tail; \
        p_mii_rxd :> tail; \
                            \
        if (taillen & ~0x7) { \
            num_rx_bytes += (taillen>>3); \
                                            \
            /* Ensure that the mask is byte-aligned */ \
            unsigned mask = ~0U >> (taillen & ~0x7); \
                                                     \
            /* Correct for non byte-aligned frames */ \
            tail <<= taillen & 0x7; \
                                    \
            /* Mask out junk bits in last input */ \
            tail &= ~mask; \
                            \
            /* Incorporate tailbits of input data, see https://github.com/xcore/doc_tips_and_tricks for details. */ \
            { tail, crc } = mac(crc, mask, tail, crc); \
            crc32(crc, tail, poly); \
        } \
            \
        buf->length = num_rx_bytes; \
        buf->crc = crc; \
                         \
        if (dptr != end_ptr) { \
            /* Update where the write pointer is in memory */ \
            mii_commit(rx_mem, dptr); \
                                        \
            /* Record the fact that there is a valid packet ready for filtering */ \
            /*  - the assumption is that the filtering is running fast enough */ \
            /*    to keep up and process the packets so that the incoming_packet */ \
            /*    pointers never fill up */ \
            mii_add_packet(incoming_packets, buf); \
        } \
    } \
return; \
}
// END OF MASTER_RX_CHUNK_TAIL


unsafe void rmii_master_rx_pins_4b( mii_mempool_t rx_mem,
                                    mii_packet_queue_t incoming_packets,
                                    unsigned * unsafe rdptr,
                                    in port p_mii_rxdv,
                                    in buffered port:32 * unsafe p_mii_rxd,
                                    rmii_data_4b_pin_assignment_t rx_port_4b_pins){
    printstr("rmii_master_rx_pins_4b\n");
    printstr("rmii_master_rx_pins_1b\n");
    printstr("RX Using 4b port. Pins: ");printstrln(rx_port_4b_pins == USE_LOWER_2B ? "USE_LOWER_2B" : "USE_UPPER_2B");
    printhexln((unsigned)*p_mii_rxd);

    MASTER_RX_CHUNK_HEAD

    p_mii_rxd when pinseq(0xD) :> sfd_preamble;

    if (((sfd_preamble >> 24) & 0xFF) != 0xD5) {
        /* Corrupt the CRC so that the packet is discarded */
        crc = ~crc;
    }

    /* Timestamp the start of packet and record it in the packet structure */
    unsigned time;
    tmr :> time;
    buf->timestamp = time;

    unsigned end_of_frame = 0;
    unsigned word;

    do {
        select {
           case p_mii_rxd :> word:
                crc32(crc, word, poly);

                /* Prevent the overwriting of packets in the buffer. If the end_ptr is reached
                * then this packet will be dropped as there is not enough room in the buffer. */
                if (dptr != end_ptr) {
                    *dptr = word;
                    dptr++;
                    /* The wrap pointer contains the address of the start of the buffer */
                    if (dptr == wrap_ptr)
                        dptr = (unsigned * unsafe) *dptr;
                }

                num_rx_bytes += 4;
                break;

           case p_mii_rxdv when pinseq(0) :> int:
                end_of_frame = 1;
                break;
        }
    } while (!end_of_frame);

    /* Clear interrupts used by rx_err port handler */
    asm("clrsr 0x2");

    /* If the rx_err port detects an error then drop the packet */
    if (*error_ptr) {
        endin(p_mii_rxd);
        p_mii_rxd :> void;
        *error_ptr = 0;
        continue;
    }

    /* Note: we don't store the last word since it contains the CRC and
     * we don't need it from this point on. */
    unsigned taillen = endin(p_mii_rxd);

    MASTER_RX_CHUNK_TAIL
}



unsafe void rmii_master_rx_pins_1b( mii_mempool_t rx_mem,
                                    mii_packet_queue_t incoming_packets,
                                    unsigned * unsafe rdptr,
                                    in port p_mii_rxdv,
                                    in buffered port:32 * unsafe p_mii_rxd_0,
                                    in buffered port:32 * unsafe p_mii_rxd_1){
    printstrln("RX Using 1b ports.");
    printhexln((unsigned)*p_mii_rxd_0);
    printhexln((unsigned)*p_mii_rxd_1);
}

unsafe void rmii_master_tx_pins_4b( mii_mempool_t tx_mem_lp,
                                    mii_mempool_t tx_mem_hp,
                                    mii_packet_queue_t hp_packets,
                                    mii_packet_queue_t lp_packets,
                                    mii_ts_queue_t ts_queue_lp,
                                    out buffered port:32 * unsafe p_mii_txd,
                                    rmii_data_4b_pin_assignment_t tx_port_4b_pins,
                                    volatile ethernet_port_state_t * unsafe p_port_state){
    printstr("rmii_master_tx_pins_4b\n");
    printstr("TX Using 4b port. Pins: ");printstrln(tx_port_4b_pins == USE_LOWER_2B ? "USE_LOWER_2B" : "USE_UPPER_2B");
    printhexln((unsigned)*p_mii_txd);
}

unsafe void rmii_master_tx_pins_1b( mii_mempool_t tx_mem_lp,
                                    mii_mempool_t tx_mem_hp,
                                    mii_packet_queue_t hp_packets,
                                    mii_packet_queue_t lp_packets,
                                    mii_ts_queue_t ts_queue_lp,
                                    out buffered port:32 * unsafe p_mii_txd_0,
                                    out buffered port:32 * unsafe p_mii_txd_1,
                                    volatile ethernet_port_state_t * unsafe p_port_state){
    printstr("rmii_master_tx_pins_1b\n");
    printstrln("TX Using 1b ports.");
    printhexln((unsigned)*p_mii_txd_0);
    printhexln((unsigned)*p_mii_txd_1);
}
