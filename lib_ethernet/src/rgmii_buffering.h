// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#ifndef __RGMII_BUFFERING_H__
#define __RGMII_BUFFERING_H__

#include <xccompat.h>
#include <stdint.h>
#include "rgmii.h"
#include "ethernet.h"
#include "default_ethernet_conf.h"
#include "client_state.h"
#include "swlock.h"
#include "hwlock.h"

void rgmii_init_lock();

#ifdef __XC__
extern "C" {
#endif

typedef struct buffers_free_t {
  unsigned top_index;
  uintptr_t *stack;
} buffers_free_t;

typedef struct buffers_used_t {
  unsigned tail_index;
  unsigned head_index;
  uintptr_t *pointers;
} buffers_used_t;

#ifdef __XC__
}
#endif

void buffers_free_initialize(REFERENCE_PARAM(buffers_free_t, free), unsigned char *buffer,
                             unsigned *pointers, unsigned buffer_count);

void buffers_used_initialize(REFERENCE_PARAM(buffers_used_t, used), unsigned *pointers);

void empty_channel(streaming_chanend_t c);

#ifdef __XC__
unsafe void rgmii_buffer_manager(streaming chanend c_rx,
                                 streaming chanend c_speed_change,
                                 buffers_used_t &used_buffers_rx_lp,
                                 buffers_used_t &used_buffers_rx_hp,
                                 buffers_free_t &free_buffers,
                                 unsigned filter_num);

unsafe void rgmii_ethernet_rx_server(rx_client_state_t client_state_lp[n_rx_lp],
                                     server ethernet_rx_if i_rx_lp[n_rx_lp], unsigned n_rx_lp,
                                     streaming chanend ? c_rx_hp,
                                     streaming chanend c_rgmii_cfg,
                                     out port p_txclk_out,
                                     in buffered port:4 p_rxd_interframe,
                                     buffers_used_t &used_buffers_rx_lp,
                                     buffers_used_t &used_buffers_rx_hp,
                                     buffers_free_t &free_buffers,
                                     rgmii_inband_status_t &current_mode, int speed_change_ids[6],
                                     volatile ethernet_port_state_t * unsafe p_port_state);

unsafe void rgmii_ethernet_tx_server(tx_client_state_t client_state_lp[n_tx_lp],
                                     server ethernet_tx_if i_tx_lp[n_tx_lp], unsigned n_tx_lp,
                                     streaming chanend ? c_tx_hp,
                                     streaming chanend c_tx_to_mac,
                                     streaming chanend c_speed_change,
                                     buffers_used_t &used_buffers_tx_lp,
                                     buffers_free_t &free_buffers_lp,
                                     buffers_used_t &used_buffers_tx_hp,
                                     buffers_free_t &free_buffers_hp,
                                     volatile ethernet_port_state_t * unsafe p_port_state);
#endif

#endif // __RGMII_BUFFERING_H__
