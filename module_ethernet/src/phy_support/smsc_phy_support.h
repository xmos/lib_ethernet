#ifndef __smsc_phy_support_h__
#define __smsc_phy_support_h__
#include "ethernet.h"
#include "smi.h"
#include "otp_board_info.h"

[[combinable]]
void smsc_LAN8710_driver(smi_ports_t &smi_ports,
                         ethernet_reset_port_t p_reset,
                         client ethernet_config_if i_config,
                         unsigned phy_address);

#endif // __smsc_phy_support_h__
