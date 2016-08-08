// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#ifndef __mii_master_h__
#define __mii_master_h__
#include "mii_buffering.h"
#include "mii_ts_queue.h"
#include "server_state.h"

#ifdef __XC__

void mii_master_init(in port p_rxclk, in buffered port:32 p_rxd, in port p_rxdv,
                     clock clk_rx,
                     in port p_txclk, out port p_txen, out buffered port:32 p_txd,
                     clock clk_tx,
                     in buffered port:1  p_rxer);

unsafe void mii_master_rx_pins(mii_mempool_t rx_mem,
                               mii_packet_queue_t incoming_packets,
                               unsigned * unsafe rdptr,
                               in port p_mii_rxdv,
                               in buffered port:32 p_mii_rxd,
                               in buffered port:1 p_rxer,
                               streaming chanend c);

unsafe void mii_master_tx_pins(mii_mempool_t tx_mem_lp,
                               mii_mempool_t tx_mem_hp,
                               mii_packet_queue_t hp_packets,
                               mii_packet_queue_t lp_packets,
                               mii_ts_queue_t ts_queue_lp,
                               out buffered port:32 p_mii_txd,
                               volatile ethernet_port_state_t * unsafe p_port_state);

#endif

#endif // __mii_master_h__
