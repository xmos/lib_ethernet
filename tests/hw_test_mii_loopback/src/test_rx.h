// Copyright 2013-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __icmp_h__
#define __icmp_h__
#include <ethernet.h>
#include <otp_board_info.h>


typedef interface loopback_if {
  [[notification]] slave void packet_ready();
  [[clears_notification]] void get_packet(unsigned &len, uintptr_t &buf);
} loopback_if;

void test_rx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 unsigned client_num,
                 chanend c_xscope_control,
                 server loopback_if i_loopback);

void test_rx_hp(client ethernet_cfg_if cfg,
                streaming chanend c_rx_hp,
                unsigned client_num,
                chanend c_xscope_control,
                server loopback_if i_loopback);


void test_rx_loopback(streaming chanend c_tx_hp,
                      client loopback_if i_loopback);

#endif // __icmp_h__
