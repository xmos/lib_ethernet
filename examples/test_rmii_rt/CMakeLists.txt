cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(test_rmii)

set(APP_HW_TARGET           XCORE-AI-EXPLORER)

include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

set(APP_PCA_ENABLE          ON)

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -DETHERNET_SUPPORT_HP_QUEUES=1)

set(APP_COMPILER_FLAGS          ${COMPILER_FLAGS_COMMON})
set(APP_COMPILER_FLAGS_icmp.xc  ${COMPILER_FLAGS_COMMON}
                                -Wno-reinterpret-alignment)

set(APP_XSCOPE_SRCS         src/config.xscope)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
