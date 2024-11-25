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
#define PAD_DELAY_RECEIVE    0
#define PAD_DELAY_TRANSMIT   0
#define CLK_DELAY_RECEIVE    0
#define CLK_DELAY_TRANSMIT   7  // Note: used to be 2 (improved simulator?)
// After-init delay (used at the end of mii_init)
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


static void rmii_master_init_rx_common(){

}


void rmii_master_init_rx_4b(in port p_clk,
                            in buffered port:32 * unsafe rx_data_0,
                            rmii_data_4b_pin_assignment_t rx_port_4b_pins,
                            in port p_rxdv,
                            clock rxclk){
    rmii_master_init_rx_common();
}

void rmii_master_init_rx_1b(in port p_clk,
                            in buffered port:32 * unsafe rx_data_0,
                            in buffered port:32 * unsafe rx_data_1,
                            in port p_rxdv,
                            clock rxclk){
    rmii_master_init_rx_common();
}

static void rmii_master_init_tx_common(){

}


void rmii_master_init_tx_4b(in port p_clk,
                            out buffered port:32 * unsafe tx_data_0,
                            rmii_data_4b_pin_assignment_t tx_port_4b_pins,
                            out port p_txen,
                            clock txclk){
    rmii_master_init_tx_common();
}

void rmii_master_init_tx_1b(in port p_clk,
                            out buffered port:32 * unsafe tx_data_0,
                            out buffered port:32 * unsafe tx_data_1,
                            out port p_txen,
                            clock txclk){
    rmii_master_init_tx_common();
}

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
