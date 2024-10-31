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
# -I$(SHARED_CODE

set(APP_COMPILER_FLAGS                  ${COMPILER_FLAGS_COMMON})

set(APP_COMPILER_FLAGS_rt_mii.xc        ${COMPILER_FLAGS_COMMON} -DRT=1 -DRGMII=0)
set(APP_COMPILER_FLAGS_rt_hp_mii.xc     ${COMPILER_FLAGS_COMMON} -DRT=1 -DRGMII=0 -DETHERNET_SUPPORT_HP_QUEUES=1)
set(APP_COMPILER_FLAGS_standard_mii.xc  ${COMPILER_FLAGS_COMMON} -DRT=0 -DRGMII=0)

set(XMOS_SANDBOX_DIR                    ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()


#  support xs1 and xs2 configs
# XCC_FLAGS_rt_mii_xs1       = $(COMMON_FLAGS) -DRT=1 -DRGMII=0
# XCC_FLAGS_rt_hp_mii_xs1    = $(COMMON_FLAGS) -DRT=1 -DRGMII=0 -DETHERNET_SUPPORT_HP_QUEUES=1
# XCC_FLAGS_standard_mii_xs1 = $(COMMON_FLAGS) -DRT=0 -DRGMII=0

# XCC_FLAGS_rt_mii_xs2       = $(COMMON_FLAGS) -DRT=1 -DRGMII=0
# XCC_FLAGS_rt_hp_mii_xs2    = $(COMMON_FLAGS) -DRT=1 -DRGMII=0 -DETHERNET_SUPPORT_HP_QUEUES=1
# XCC_FLAGS_standard_mii_xs2 = $(COMMON_FLAGS) -DRT=0 -DRGMII=0

# XCC_FLAGS_rt_rgmii_xs2     = $(COMMON_FLAGS) -DRT=0 -DRGMII=1 -fno-xta-info
# XCC_FLAGS_rt_hp_rgmii_xs2  = $(COMMON_FLAGS) -DRT=0 -DRGMII=1 -DETHERNET_SUPPORT_HP_QUEUES=1 -fno-xta-info


