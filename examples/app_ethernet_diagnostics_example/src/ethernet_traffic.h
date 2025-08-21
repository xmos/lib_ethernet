// Copyright 2013-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __ETHERNET_TRAFFIC_H__
#define __ETHERNET_TRAFFIC_H__

// Library headers
#include "ethernet.h"

[[combinable]]
void ethernet_traffic(client ethernet_cfg_if cfg,
                      client ethernet_rx_if rx,
                      client ethernet_tx_if tx,
                      const unsigned char ip_address[4],
                      const unsigned char mac_address[MACADDR_NUM_BYTES]);

#endif // __ETHERNET_TRAFFIC_H__
