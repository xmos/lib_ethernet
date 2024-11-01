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

set(XMOS_SANDBOX_DIR                    ${CMAKE_CURRENT_LIST_DIR}/../../..)

file(READ ${CMAKE_CURRENT_LIST_DIR}/test_params.json JSON_CONTENT)
string(JSON PROFILES_LIST GET ${JSON_CONTENT} PROFILES)
string(JSON NUM_PROFILES LENGTH ${PROFILES_LIST})
math(EXPR NUM_PROFILES "${NUM_PROFILES} - 1")


foreach(i RANGE 0 ${NUM_PROFILES})
    string(JSON PROFILE GET ${PROFILES_LIST} ${i})
    string(JSON phy GET ${PROFILE} phy)
    string(JSON clk GET ${PROFILE} clk)
    string(JSON mac GET ${PROFILE} mac)
    string(JSON arch GET ${PROFILE} arch)
    set(config "${mac}_${phy}")
    message(STATUS "Building cfg_name: ${config}")

    set(APP_COMPILER_FLAGS_${config}    ${COMPILER_FLAGS_COMMON})


# set(APP_COMPILER_FLAGS_rt_mii           ${COMPILER_FLAGS_COMMON} -DRT=1 -DRGMII=0)
# set(APP_COMPILER_FLAGS_rt_hp_mii        ${COMPILER_FLAGS_COMMON} -DRT=1 -DRGMII=0 -DETHERNET_SUPPORT_HP_QUEUES=1)
# set(APP_COMPILER_FLAGS_standard_mii     ${COMPILER_FLAGS_COMMON} -DRT=0 -DRGMII=0)

# set(APP_COMPILER_FLAGS_rt_rgmii         ${COMPILER_FLAGS_COMMON} -DRT=0 -DRGMII=1)
# set(APP_COMPILER_FLAGS_rt_hp_rgmii      ${COMPILER_FLAGS_COMMON} -DRT=0 -DRGMII=1 -DETHERNET_SUPPORT_HP_QUEUES=1)

    string(FIND "${PROFILE}" "rt" position)
    if(position GREATER -1)
        list(APPEND APP_COMPILER_FLAGS_${config} -DRT=1)
    else()
        list(APPEND APP_COMPILER_FLAGS_${config} -DRT=0)
    endif()

    string(FIND "${PROFILE}" "hp" position)
    if(position GREATER -1)
        list(APPEND APP_COMPILER_FLAGS_${config} -DETHERNET_SUPPORT_HP_QUEUES=1)
    else()
        list(APPEND APP_COMPILER_FLAGS_${config} -DETHERNET_SUPPORT_HP_QUEUES=0)
    endif()

    if(${phy} MATCHES "rgmii")
        list(APPEND APP_COMPILER_FLAGS_${config} -DRGMII=1)
    else()
        list(APPEND APP_COMPILER_FLAGS_${config} -DRGMII=0)
    endif()

    message(STATUS "FLAGS: ${APP_COMPILER_FLAGS_${config}}")
endforeach()

XMOS_REGISTER_APP()
