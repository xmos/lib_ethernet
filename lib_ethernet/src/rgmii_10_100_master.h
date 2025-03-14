// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __RGMII_10_100_MASTER_H__
#define __RGMII_10_100_MASTER_H__

#ifdef __XC__

unsafe void rgmii_10_100_master_rx_pins(streaming chanend c,
                                        in buffered port:32 p_rxd_10_100,
                                        in port p_rxdv,
                                        in buffered port:1 p_rxer,
                                        streaming chanend c_speed_change);

unsafe void rgmii_10_100_master_tx_pins(streaming chanend c,
                                        out buffered port:32 p_txd,
                                        streaming chanend c_speed_change);

#endif

#endif
