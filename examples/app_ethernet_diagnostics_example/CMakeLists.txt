cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(app_ethernet_diagnostics_example)

set(APP_HW_TARGET           xk-eth-316-dual.xn)

include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

set(APP_PCA_ENABLE ON)

set(COMPILER_FLAGS_COMMON   -g
                            -Os
                            -Wall
                            -Wdiv-by-zero
                            -Wfloat-equal
                            -DBOARD_SUPPORT_BOARD=XK_ETH_316_DUAL
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -DDEBUG_PRINT_ENABLE_xk_eth_316_dual=1
                            -DXASSERT_ENABLE_DEBUG=1)

set(APP_COMPILER_FLAGS      ${COMPILER_FLAGS_COMMON})

set(APP_XSCOPE_SRCS         src/config.xscope)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
