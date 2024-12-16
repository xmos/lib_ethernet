// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef _phy_support_h_
#define _phy_support_h_
#include <stdint.h>
#include "ethernet.h"
#include "smi.h"
#include <xccompat.h>
#include "doxygen.h"    // Sphynx Documentation Workarounds

[[combinable]]
void lan8710a_phy_driver(client interface smi_if smi,
                         client interface ethernet_cfg_if eth);


[[combinable]]
void ar8035_phy_driver(client interface smi_if smi,
                       client interface ethernet_cfg_if eth,
                       out_port_t p_eth_reset);

[[combinable]]
void dp83826e_phy_driver(client interface smi_if smi,
                         client interface ethernet_cfg_if eth,
                         out_port_t p_eth_reset);


#endif // _phy_support_h_
