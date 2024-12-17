cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(test_rmii_dual)

set(APP_HW_TARGET           src/XCORE-AI-EXPLORER.xn)

include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

set(APP_PCA_ENABLE          ON)

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -DETHERNET_SUPPORT_HP_QUEUES=1
                            -Wno-unused-function
                            )


set(APP_COMPILER_FLAGS_tx4b_rx4b        ${COMPILER_FLAGS_COMMON} -DTX_WIDTH=4 -DRX_WIDTH=4)
set(APP_COMPILER_FLAGS_tx4b_rx4b_upper  ${COMPILER_FLAGS_COMMON} -DTX_WIDTH=4 -DRX_WIDTH=4 -DUSE_LOWER=0)
set(APP_COMPILER_FLAGS_tx1b_rx4b        ${COMPILER_FLAGS_COMMON} -DTX_WIDTH=1 -DRX_WIDTH=4)
set(APP_COMPILER_FLAGS_tx4b_rx1b        ${COMPILER_FLAGS_COMMON} -DTX_WIDTH=4 -DRX_WIDTH=1)
set(APP_COMPILER_FLAGS_tx1b_rx1b        ${COMPILER_FLAGS_COMMON} -DTX_WIDTH=1 -DRX_WIDTH=1)

set(APP_XSCOPE_SRCS         src/config.xscope)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
