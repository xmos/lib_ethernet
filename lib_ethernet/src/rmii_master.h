// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __rmii_master_h__
#define __rmii_master_h__
#include "mii_buffering.h"
#include "mii_ts_queue.h"
#include "server_state.h"

#ifdef __XC__

void rmii_master_init_rx_4b(in port p_clk,
                            in buffered port:32 * unsafe rx_data_0,
                            rmii_data_4b_pin_assignment_t rx_port_4b_pins,
                            in port p_rxdv,
                            clock rxclk);

void rmii_master_init_rx_1b(in port p_clk,
                            in buffered port:32 * unsafe rx_data_0,
                            in buffered port:32 * unsafe rx_data_1,
                            in port p_rxdv,
                            clock rxclk);

void rmii_master_init_tx_4b(in port p_clk,
                            out buffered port:32 * unsafe tx_data_0,
                            rmii_data_4b_pin_assignment_t tx_port_4b_pins,
                            out port p_txen,
                            clock txclk);

void rmii_master_init_tx_1b(in port p_clk,
                            out buffered port:32 * unsafe tx_data_0,
                            out buffered port:32 * unsafe tx_data_1,
                            out port p_txen,
                            clock txclk);

unsafe void rmii_master_rx_pins(mii_mempool_t rx_mem,
                                mii_packet_queue_t incoming_packets,
                                unsigned * unsafe rdptr,
                                in port p_mii_rxdv,
                                in buffered port:32 p_mii_rxd,
                                in buffered port:1 p_rxer);

unsafe void rmii_master_tx_pins(mii_mempool_t tx_mem_lp,
                                mii_mempool_t tx_mem_hp,
                                mii_packet_queue_t hp_packets,
                                mii_packet_queue_t lp_packets,
                                mii_ts_queue_t ts_queue_lp,
                                out buffered port:32 p_mii_txd,
                                volatile ethernet_port_state_t * unsafe p_port_state);

#endif

#endif // __rmii_master_h__
