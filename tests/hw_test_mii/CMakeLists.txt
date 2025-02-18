cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(hw_test_mii)

set(APP_HW_TARGET           xk-eth-xu316-dual-100m.xn)

include(${CMAKE_CURRENT_LIST_DIR}/../../examples/deps.cmake)

set(APP_PCA_ENABLE ON)

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -Os
                            -Wno-reinterpret-alignment
                            -DENABLE_DUT_TIMEOUT=0
                            -fxscope
                            -DBOARD_SUPPORT_BOARD=XK_ETH_XU316_DUAL_100M
                            )

set(APP_COMPILER_FLAGS_rx_only                 ${COMPILER_FLAGS_COMMON})
set(APP_COMPILER_FLAGS_rx_multiple_queues      ${COMPILER_FLAGS_COMMON} -DMULTIPLE_QUEUES=1 -DETHERNET_SUPPORT_HP_QUEUES=1)
set(APP_COMPILER_FLAGS_loopback                ${COMPILER_FLAGS_COMMON} -DLOOPBACK=1)

set(APP_XSCOPE_SRCS src/config.xscope)

set(APP_INCLUDES src/xscope_control src/phy_driver)

set(XMOS_SANDBOX_DIR    ${CMAKE_CURRENT_LIST_DIR}/../../..)

message(STATUS "CMAKE_CURRENT_BINARY_DIR = ${CMAKE_CURRENT_BINARY_DIR}")

XMOS_REGISTER_APP()
