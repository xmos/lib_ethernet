cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(AN00120_100Mbit_ethernet_demo_rmii)

set(APP_HW_TARGET           xk-eth-xu316-dual-100m.xn)

include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

set(APP_PCA_ENABLE ON)

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -Os
                            -Wno-reinterpret-alignment
                            -DBOARD_SUPPORT_BOARD=XK_ETH_XU316_DUAL_100M)

set(APP_COMPILER_FLAGS      ${COMPILER_FLAGS_COMMON})

set(APP_XSCOPE_SRCS src/config.xscope)

set(XMOS_SANDBOX_DIR    ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
