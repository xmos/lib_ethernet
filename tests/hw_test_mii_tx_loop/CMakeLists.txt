cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(hw_test_mii_tx_loop)

set(APP_HW_TARGET           SLICEKIT-ETH-TRIANGLE1.xn)

include(${CMAKE_CURRENT_LIST_DIR}/../../examples/deps.cmake)

set(APP_PCA_ENABLE ON)

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -Os
                            -Wno-reinterpret-alignment
                            -DENABLE_DUT_TIMEOUT=0
                            -DETHERNET_SUPPORT_TRAFFIC_SHAPER=1
							-DETHERNET_SUPPORT_HP_QUEUES=1
							-fxscope
                            )

set(APP_COMPILER_FLAGS      ${COMPILER_FLAGS_COMMON})

set(APP_XSCOPE_SRCS src/config.xscope)

file(GLOB XC_SOURCES RELATIVE ${CMAKE_CURRENT_LIST_DIR} "src/*.xc")
file(GLOB COMMON_SOURCES RELATIVE ${CMAKE_CURRENT_LIST_DIR} "${CMAKE_CURRENT_LIST_DIR}/../hw_test_mii/src/xscope_control/*.xc")
list(APPEND XC_SOURCES ${COMMON_SOURCES})

set(APP_XC_SRCS ${XC_SOURCES})
set(APP_INCLUDES src ../hw_test_mii/src/xscope_control)

set(XMOS_SANDBOX_DIR    ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
