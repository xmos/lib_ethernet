cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(test_smi)

set(APP_PCA_ENABLE ON)

include(../helpers.cmake)
include(../test_deps.cmake)

file(GLOB_RECURSE SOURCES_XC RELATIVE  ${CMAKE_CURRENT_LIST_DIR} "src/*.xc")
set(APP_XC_SRCS             ${SOURCES_XC})
set(APP_INCLUDES            ../include src)


set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -Os
                            -D__SIMULATOR__=1)

set(XMOS_SANDBOX_DIR                    ${CMAKE_CURRENT_LIST_DIR}/../../..)

file(READ ${CMAKE_CURRENT_LIST_DIR}/test_params.json JSON_CONTENT)

get_json_list(${JSON_CONTENT} PROFILES profile_list)

set(done_configs "")
foreach(PROFILE ${profile_list})
    string(JSON type GET ${PROFILE} type)
    get_json_list(${PROFILE} arch arch_list) # Get archs to build for, for this particular profile
    foreach(arch ${arch_list})
        set(config "${type}_${arch}")
        message(STATUS "Building cfg_name: ${config}")

        set_app_hw_target(arch)
        set(APP_COMPILER_FLAGS_${config}    ${COMPILER_FLAGS_COMMON})

        string(FIND "${PROFILE}" "single" position)
        if(position GREATER -1)
            list(APPEND APP_COMPILER_FLAGS_${config} -DSINGLE_PORT=1)
        else()
            list(APPEND APP_COMPILER_FLAGS_${config} -DTWO_PORTS=1)
        endif()


        message(STATUS APP_COMPILER_FLAGS_${config} ${APP_COMPILER_FLAGS_${config}})

        XMOS_REGISTER_APP()
        unset(APP_COMPILER_FLAGS_${config})

    endforeach() # foreach(arch ${arch_list})
    unset(arch_list)
endforeach() # foreach(PROFILE ${profile_list})
