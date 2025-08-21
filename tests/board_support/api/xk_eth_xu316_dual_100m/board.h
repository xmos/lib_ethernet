// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef __XK_ETH_XU316_DUAL_100M_BOARD_H__
#define __XK_ETH_XU316_DUAL_100M_BOARD_H__

#include "test_boards_utils.h"
#if (TEST_BOARD_SUPPORT_BOARD == XK_ETH_XU316_DUAL_100M) || defined(__DOXYGEN__)
#include <xccompat.h>
#include "smi.h"

#ifndef NULLABLE_CLIENT_INTERFACE
#ifdef __XC__
#define NULLABLE_CLIENT_INTERFACE(tag, name) client interface tag ?name
#else
#define NULLABLE_CLIENT_INTERFACE(type, name) unsigned name
#endif
#endif // NULLABLE_CLIENT_INTERFACE


/**
 * \addtogroup xk_eth_xu316_dual_100m
 *
 * API for the xk_eth_xu316_dual_100m board.
 * @{
 */

 /** Index value used with get_port_timings() to refer to board configuration.
  *
  * The timings change according to which PHYs mounted and the hardware configuration
  * of the dual PHY dev-kit.
  */
typedef enum {
    DUAL_PHY_MOUNTED_PHY0,
    DUAL_PHY_MOUNTED_PHY1,
    SINGLE_PHY_MOUNTED_PHY0,
} port_timing_index_t;

/** Task that connects to the SMI master and MAC to configure the
 * DP83826E PHYs and monitor the link status. Note this task is combinable
 * (typically with SMI) and therefore does not need to take a whole thread.
 *
 * Note it may be necessary to modify R3 and R23 according to which
 * PHY is used. Populate R23 and remove R3 for PHY_0 only populated otherwise
 * populate R3 and remove R23 for all other settings.
 *
 *  \param i_smi        Client register read/write interface
 *  \param i_eth_phy_0  Client MAC configuration interface for PHY_0. Set to NULL if unused.
 *  \param i_eth_phy_1  Client MAC configuration interface for PHY_1. Set to NULL if unused.
 */
[[combinable]]
void dual_dp83826e_phy_driver(CLIENT_INTERFACE(smi_if, i_smi),
                              NULLABLE_CLIENT_INTERFACE(ethernet_cfg_if, i_eth_phy_0),
                              NULLABLE_CLIENT_INTERFACE(ethernet_cfg_if, i_eth_phy_1));

/** Sends hard reset to both PHYs. Both PHYs will be ready for SMI
 * communication once this function has returned.
 * This function must be called from Tile[1].
 *
 */
void reset_eth_phys(void);

/** Returns a timing struct tuned to the xk_eth_xu316_dual_100m hardware.
 * This struct should be passed to the call to rmii_ethernet_rt_mac() and will
 * ensure setup and hold times are maximised at the pin level of the PHY connection.
 * rmii_port_timing_t is defined in lib_ethernet.
 *
 *  \param phy_idx      The index of the PHY to get timing data about.
 *  \returns            The timing struct to be passed to the PHY.
 */
rmii_port_timing_t get_port_timings(port_timing_index_t phy_idx);


/**@}*/ // END: addtogroup xk_eth_xu316_dual_100m

#endif // (TEST_BOARD_SUPPORT_BOARD == XK_ETH_XU316_DUAL_100M) || defined(__DOXYGEN__)


#endif // __XK_ETH_XU316_DUAL_100M_BOARD_H__
