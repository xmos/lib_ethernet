cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(app_bringup_xk_eth_xu316_dual_100m)

include(${CMAKE_CURRENT_LIST_DIR}/../board_support/board_support.cmake)

set(APP_HW_TARGET                   xk-eth-xu316-dual-100m.xn)

set(APP_DEPENDENT_MODULES           lib_ethernet
                                    "lib_board_support(1.3.0)")
set(APP_PCA_ENABLE ON)

set(COMPILER_FLAGS_COMMON           -g
                                    -report
                                    -DDEBUG_PRINT_ENABLE=1
                                    -Os
                                    -Wno-reinterpret-alignment
                                    -DTEST_BOARD_SUPPORT_BOARD=XK_ETH_XU316_DUAL_100M)

set(APP_COMPILER_FLAGS_MAC_0                -DPHY0=1 ${COMPILER_FLAGS_COMMON})
set(APP_COMPILER_FLAGS_MAC_0_SINGLE_SMI     -DPHY0=1 -DSINGLE_SMI=1 ${COMPILER_FLAGS_COMMON})
set(APP_COMPILER_FLAGS_MAC_1                -DPHY1=1 ${COMPILER_FLAGS_COMMON})
set(APP_COMPILER_FLAGS_MAC_1_8B_TX          -DPHY1=1 -DPHY1_8B_TX=1 ${COMPILER_FLAGS_COMMON})
set(APP_COMPILER_FLAGS_MAC_0_MAC_1          -DPHY0=1 -DPHY1=1 ${COMPILER_FLAGS_COMMON})

set(APP_XSCOPE_SRCS                 src/config.xscope)

set(APP_XC_SRCS                     src/main.xc src/icmp.xc ${test_board_support_SRCS})
set(APP_INCLUDES                    ${test_board_support_INC})

set(XMOS_SANDBOX_DIR                ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
