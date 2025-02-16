#ifndef PHY_DRIVER_H
#define PHY_DRIVER_H

[[combinable]]
void lan8710a_phy_driver(client interface smi_if smi,
                         client interface ethernet_cfg_if eth);

#endif
