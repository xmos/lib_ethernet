// Copyright 2013-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __icmp_h__
#define __icmp_h__
#include <ethernet.h>
#include <otp_board_info.h>


void test_rx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx);

void test_rx_hp(client ethernet_cfg_if cfg,
                 streaming chanend c_rx_hp,
                 unsigned num_lp_clients);

#endif // __icmp_h__
