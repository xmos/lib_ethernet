// Copyright 2024-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#pragma once

#include <xs1.h>

#ifdef __test_board_support_conf_h_exists__
    #include "test_board_support_conf.h"
#endif

/**
 * \addtogroup test_bs_common
 *
 * The common defines for using test_board_support.
 * @{
 */

/* List of supported boards */

/** Define representing Null board i.e. no board in use*/
#define NULL_BOARD                  0

/** Define representing XK-ETH-XU316-DUAL-100M board */
#define XK_ETH_XU316_DUAL_100M      0xF0

/** Total number of boards supported by the library */
#define TEST_BOARD_SUPPORT_N_BOARDS 1  // max board + 1

/** Define that should be set to the current board type in use
  *
  * Default value: NULL_BOARD
  */
#ifndef TEST_BOARD_SUPPORT_BOARD
#define TEST_BOARD_SUPPORT_BOARD    NULL_BOARD /** This means none of the BSP sources are compiled in to the project */
#endif

#if TEST_BOARD_SUPPORT_BOARD != XK_ETH_XU316_DUAL_100M
#error Invalid board selected
#endif

/**@}*/ // END: addtogroup test_bs_common
