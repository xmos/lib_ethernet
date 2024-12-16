// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef _phy_support_h_
#define _phy_support_h_
#include <stdint.h>
#include "ethernet.h"
#include "smi.h"
#include <xccompat.h>
#include "doxygen.h"    // Sphynx Documentation Workarounds


/**
 * \addtogroup phy_drivers_if
 * @{
 */


/** Task that connects to the SMI master and MAC to configure the
 * lan8710a PHY and monitor the link status.
 *
 *  \param i_smi    Client register read/write interface
 *  \param i_eth    Client MAC configuration interface
 */
[[combinable]]
void lan8710a_phy_driver(CLIENT_INTERFACE(smi_if, i_smi),
                         CLIENT_INTERFACE(ethernet_cfg_if, i_eth));


/** Task that connects to the SMI master and MAC to configure the
 * ar8035 PHY and monitor the link status.
 *
 *  \param i_smi        Client register read/write interface
 *  \param i_eth        Client MAC configuration interface
 *  \param p_eth_reset  Port connected to the PHY reset pin
 */
[[combinable]]
void ar8035_phy_driver(CLIENT_INTERFACE(smi_if, i_smi),
                       CLIENT_INTERFACE(ethernet_cfg_if i_eth),
                       out_port_t p_eth_reset);


/** Task that connects to the SMI master and MAC to configure the
 * dp83826e PHY and monitor the link status.
 *
 *  \param i_smi    Client register read/write interface
 *  \param i_eth    Client MAC configuration interface
 */
[[combinable]]
void dp83826e_phy_driver(CLIENT_INTERFACE(smi_if i_smi),
                         CLIENT_INTERFACE(ethernet_cfg_if i_eth));


/**@}*/ // END: addtogroup phy_drivers_if



#endif // _phy_support_h_
