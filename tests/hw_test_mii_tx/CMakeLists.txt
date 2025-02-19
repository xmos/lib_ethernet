cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(hw_test_mii_tx_only)

set(APP_HW_TARGET           xk-eth-xu316-dual-100m.xn)

include(${CMAKE_CURRENT_LIST_DIR}/../../examples/deps.cmake)

set(APP_PCA_ENABLE ON)

set( AUTOGEN_DIR ${CMAKE_CURRENT_BINARY_DIR}/src.autogen )
file(RELATIVE_PATH REL_AUTOGEN_DIR ${CMAKE_CURRENT_LIST_DIR} ${AUTOGEN_DIR})

set(XSCOPE_CMDS_ENUM_GEN_SCRIPT ${CMAKE_CURRENT_LIST_DIR}/../xscope_host.py)
set(XSCOPE_CMDS_ENUM_FILE "${AUTOGEN_DIR}/xscope_cmds_enum.h")
message(STATUS "args = ${XSCOPE_CMDS_ENUM_FILE}")

add_custom_command(
    OUTPUT ${XSCOPE_CMDS_ENUM_FILE}
    COMMAND python ${XSCOPE_CMDS_ENUM_GEN_SCRIPT} ${XSCOPE_CMDS_ENUM_FILE}
    DEPENDS ${XSCOPE_CMDS_ENUM_GEN_SCRIPT}
    COMMENT "Generate xscope cmds enum file"
    VERBATIM
)

add_custom_target(xscope_cmds_enum_gen DEPENDS ${XSCOPE_CMDS_ENUM_FILE})

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -Os
                            -Wno-reinterpret-alignment
                            -DENABLE_DUT_TIMEOUT=0
                            -DETHERNET_SUPPORT_TRAFFIC_SHAPER=1
							-DETHERNET_SUPPORT_HP_QUEUES=1
							-fxscope
                            -DBOARD_SUPPORT_BOARD=XK_ETH_XU316_DUAL_100M
                            )

set(APP_COMPILER_FLAGS      ${COMPILER_FLAGS_COMMON})

set(APP_XSCOPE_SRCS src/config.xscope)

file(GLOB XC_SOURCES RELATIVE ${CMAKE_CURRENT_LIST_DIR} "src/*.xc")
file(GLOB COMMON_SOURCES RELATIVE ${CMAKE_CURRENT_LIST_DIR}
                                  "${CMAKE_CURRENT_LIST_DIR}/../hw_test_mii/src/xscope_control/*.xc"
                                  "${CMAKE_CURRENT_LIST_DIR}/../hw_test_mii/src/phy_driver/*.xc")

list(APPEND XC_SOURCES ${COMMON_SOURCES})

set(APP_XC_SRCS ${XC_SOURCES})
set(APP_INCLUDES src ../hw_test_mii/src/xscope_control ../hw_test_mii/src/phy_driver ${REL_AUTOGEN_DIR})

set(XMOS_SANDBOX_DIR    ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()

foreach(target ${APP_BUILD_TARGETS})
    add_dependencies(${target} xscope_cmds_enum_gen)
endforeach()
