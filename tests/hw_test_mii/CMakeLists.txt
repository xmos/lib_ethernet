cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(hw_test_mii)

set(APP_HW_TARGET           SLICEKIT-ETH-TRIANGLE1.xn)

include(${CMAKE_CURRENT_LIST_DIR}/../../examples/deps.cmake)

set(APP_PCA_ENABLE ON)

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -save-temps
                            -Os
                            -Wno-reinterpret-alignment
                            -DENABLE_DUT_TIMEOUT=0
                            -fxscope
                            )

set(APP_COMPILER_FLAGS_rx_only      ${COMPILER_FLAGS_COMMON})
set(APP_COMPILER_FLAGS_loopback      ${COMPILER_FLAGS_COMMON} -DLOOPBACK=1)

set(APP_XSCOPE_SRCS src/config.xscope)

set(XMOS_SANDBOX_DIR    ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
