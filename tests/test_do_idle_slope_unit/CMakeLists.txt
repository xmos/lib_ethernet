cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(test_do_idle_slope_unit)

set(APP_PCA_ENABLE ON)
include(../test_deps.cmake)

set(APP_HW_TARGET           XCORE-AI-EXPLORER)

set(APP_PCA_ENABLE          ON)

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE
                            -Os)

set(APP_COMPILER_FLAGS      ${COMPILER_FLAGS_COMMON})

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
