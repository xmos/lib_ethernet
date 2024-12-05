
cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(test_rmii_rx)

include(../helpers.cmake)

set(APP_PCA_ENABLE ON)

include(../test_deps.cmake)

file(GLOB_RECURSE SOURCES_XC RELATIVE  ${CMAKE_CURRENT_LIST_DIR} "src/*.xc")
set(APP_XC_SRCS             ${SOURCES_XC})
set(APP_INCLUDES            ../include src)

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -Os)

set(XMOS_SANDBOX_DIR                    ${CMAKE_CURRENT_LIST_DIR}/../../..)

file(READ ${CMAKE_CURRENT_LIST_DIR}/test_params.json JSON_CONTENT)

get_json_list(${JSON_CONTENT} PROFILES profile_list)

set(done_configs "")
foreach(PROFILE ${profile_list})
    get_json_list(${PROFILE} arch arch_list) # Get archs to build for, for this particular profile
    get_json_list(${PROFILE} rx_width tx_width_list)
    message(STATUS "${tx_width_list}")
    foreach(arch ${arch_list})
        foreach(rx_width ${tx_width_list})
            string(JSON phy GET ${PROFILE} phy)
            string(JSON clk GET ${PROFILE} clk)
            string(JSON mac GET ${PROFILE} mac)
            set(config "${mac}_${phy}_${rx_width}_${arch}")

            list (FIND done_configs ${config} _index)

            if(${_index} EQUAL -1) # Only build if it is a new config
                list(APPEND done_configs ${config})
                message(STATUS "Building cfg_name: ${config}")

                set(APP_HW_TARGET XCORE-AI-EXPLORER_custom.xn)

                set(APP_COMPILER_FLAGS_${config}    ${COMPILER_FLAGS_COMMON})

                set_app_rx_width(rx_width)


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

                if(${phy} MATCHES "rmii")
                    list(APPEND APP_COMPILER_FLAGS_${config} -DRMII=1)
                else()
                    list(APPEND APP_COMPILER_FLAGS_${config} -DRMII=0)
                endif()

                XMOS_REGISTER_APP()
                unset(APP_COMPILER_FLAGS_${config})
            endif() # if(${_index} equal -1) # New config
        endforeach()
    endforeach() # foreach(arch ${arch_list})
    unset(arch_list)
endforeach() # foreach(PROFILE ${profile_list})
