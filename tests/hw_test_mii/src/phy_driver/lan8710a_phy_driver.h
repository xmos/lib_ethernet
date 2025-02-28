// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef PHY_DRIVER_H
#define PHY_DRIVER_H

[[combinable]]
void lan8710a_phy_driver(client interface smi_if smi,
                         client interface ethernet_cfg_if eth);

#endif
