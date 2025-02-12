// Copyright 2013-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __tx_h__
#define __tx_h__
#include <ethernet.h>
#include <otp_board_info.h>

void test_tx_lp_loop(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 unsigned client_num,
                 chanend c_xscope_control
                 );

void xscope_control(chanend c_xscope, chanend c_clients[num_clients], static const unsigned num_clients);

#endif // __tx_h__
