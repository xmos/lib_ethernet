// Copyright 2013-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __icmp_h__
#define __icmp_h__
#include <ethernet.h>
<<<<<<< HEAD
#include <otp_board_info.h>
=======
>>>>>>> hw_test


[[combinable]]
void icmp_server(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 const unsigned char ip_address[4],
<<<<<<< HEAD
                 otp_ports_t &otp_ports);
=======
                 const unsigned char mac_address[MACADDR_NUM_BYTES]);
>>>>>>> hw_test

#endif // __icmp_h__
