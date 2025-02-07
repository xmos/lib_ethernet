// Copyright 2013-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __icmp_h__
#define __icmp_h__
#include <ethernet.h>
#include <otp_board_info.h>

enum {
    CMD_DEVICE_SHUTDOWN = 1,
    CMD_SET_DEVICE_MACADDR
};

void test_rx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 unsigned client_num,
                 chanend c_xscope_control);

void xscope_control(chanend c_xscope, chanend c_clients[num_clients], static const unsigned num_clients);

#endif // __icmp_h__
