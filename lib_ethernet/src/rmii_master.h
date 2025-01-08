// Copyright 2024-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __rmii_master_h__
#define __rmii_master_h__
#include "mii_buffering.h"
#include "mii_ts_queue.h"
#include "server_state.h"

#ifdef __XC__

unsafe void rmii_master_init_rx_4b( in port p_clk,
                                    in buffered port:32 * unsafe rx_data,
                                    in port p_rxdv,
                                    clock rxclk);

unsafe void rmii_master_init_rx_1b( in port p_clk,
                                    in buffered port:32 * unsafe rx_data_0,
                                    in buffered port:32 * unsafe rx_data_1,
                                    in port p_rxdv,
                                    clock rxclk);

unsafe void rmii_master_init_tx_4b( in port p_clk,
                                    out buffered port:32 * unsafe tx_data,
                                    out port p_txen,
                                    clock txclk);

unsafe void rmii_master_init_tx_1b( in port p_clk,
                                    out buffered port:32 * unsafe tx_data_0,
                                    out buffered port:32 * unsafe tx_data_1,
                                    out port p_txen,
                                    clock txclk);

unsafe void rmii_master_rx_pins_4b(mii_mempool_t rx_mem,
                                mii_packet_queue_t incoming_packets,
                                unsigned * unsafe rdptr,
                                in port p_mii_rxdv,
                                in buffered port:32 * unsafe p_mii_rxd,
                                rmii_data_4b_pin_assignment_t rx_port_4b_pins,
                                volatile int * unsafe running_flag_ptr,
                                chanend c_rx_pins_exit);

unsafe void rmii_master_rx_pins_1b(mii_mempool_t rx_mem,
                                mii_packet_queue_t incoming_packets,
                                unsigned * unsafe rdptr,
                                in port p_mii_rxdv,
                                in buffered port:32 * unsafe p_mii_rxd_0,
                                in buffered port:32 * unsafe p_mii_rxd_1,
                                volatile int * unsafe running_flag_ptr,
                                chanend c_rx_pins_exit);

unsafe void rmii_master_tx_pins(mii_mempool_t tx_mem_lp,
                                mii_mempool_t tx_mem_hp,
                                mii_packet_queue_t hp_packets,
                                mii_packet_queue_t lp_packets,
                                mii_ts_queue_t ts_queue_lp,
                                unsigned tx_port_width,
                                out buffered port:32 * unsafe p_mii_txd_0,
                                out buffered port:32 * unsafe  p_mii_txd_1,
                                rmii_data_4b_pin_assignment_t tx_port_4b_pins,
                                clock txclk,
                                volatile ethernet_port_state_t * unsafe p_port_state,
                                volatile int * unsafe running_flag_ptr);


// This is re-used by RMII as it is abstracted from the MAC pins
unsafe void mii_ethernet_server(mii_mempool_t rx_mem,
                               mii_packet_queue_t rx_packets_lp,
                               mii_packet_queue_t rx_packets_hp,
                               unsigned * unsafe rx_rdptr,
                               mii_mempool_t tx_mem_lp,
                               mii_mempool_t tx_mem_hp,
                               mii_packet_queue_t tx_packets_lp,
                               mii_packet_queue_t tx_packets_hp,
                               mii_ts_queue_t ts_queue_lp,
                               server ethernet_cfg_if i_cfg[n_cfg], static const unsigned n_cfg,
                               server ethernet_rx_if i_rx_lp[n_rx_lp], static const unsigned n_rx_lp,
                               server ethernet_tx_if i_tx_lp[n_tx_lp], static const unsigned n_tx_lp,
                               streaming chanend ? c_rx_hp,
                               streaming chanend ? c_tx_hp,
                               chanend c_macaddr_filter,
                               volatile ethernet_port_state_t * unsafe p_port_state,
                               volatile int * unsafe running_flag_ptr,
                               chanend c_rx_pins_exit,
                               phy_100mb_t phy_type);

#endif

#endif // __rmii_master_h__
