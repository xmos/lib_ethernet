cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(io_test)

set(APP_HW_TARGET           XCORE-AI-EXPLORER)

# set(APP_DEPENDENT_MODULES   lib_ethernet)

set(APP_PCA_ENABLE ON)

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -save-temps
                            -Os)

set(APP_COMPILER_FLAGS      ${COMPILER_FLAGS_COMMON})

set(APP_XSCOPE_SRCS         src/config.xscope)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
