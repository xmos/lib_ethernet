cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(test_tx)


set(APP_HW_TARGET           XCORE-200-EXPLORER)

set(APP_PCA_ENABLE ON)

set(APP_DEPENDENT_MODULES   lib_ethernet)

# Used libs and common code
include(../test_deps.cmake)
set(APP_XC_SRCS             src/main.xc)
set(APP_INCLUDES            ../include)

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -Os)

set(APP_COMPILER_FLAGS_rt_mii           ${COMPILER_FLAGS_COMMON} -DRT=1 -DRGMII=0)
set(APP_COMPILER_FLAGS_rt_hp_mii        ${COMPILER_FLAGS_COMMON} -DRT=1 -DRGMII=0 -DETHERNET_SUPPORT_HP_QUEUES=1)
set(APP_COMPILER_FLAGS_standard_mii     ${COMPILER_FLAGS_COMMON} -DRT=0 -DRGMII=0)

set(APP_COMPILER_FLAGS_rt_rgmii         ${COMPILER_FLAGS_COMMON} -DRT=0 -DRGMII=1)
set(APP_COMPILER_FLAGS_rt_hp_rgmii      ${COMPILER_FLAGS_COMMON} -DRT=0 -DRGMII=1 -DETHERNET_SUPPORT_HP_QUEUES=1)


set(XMOS_SANDBOX_DIR                    ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
