cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(AN00199_gigabit_ethernet_demo_explorerkit)

set(APP_HW_TARGET           XCORE-200-EXPLORER)

include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

set(APP_PCA_ENABLE          ON)

set(COMPILER_FLAGS_COMMON   -g
                            -Os
                            -report
                            -DDEBUG_PRINT_ENABLE
                            -DRGMII=1
                            -DBOARD_SUPPORT_BOARD=XK_EVK_XE216)

set(APP_COMPILER_FLAGS          ${COMPILER_FLAGS_COMMON})
set(APP_COMPILER_FLAGS_icmp.xc  ${COMPILER_FLAGS_COMMON}
                                -Wno-reinterpret-alignment)

set(APP_XSCOPE_SRCS         src/config.xscope)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
