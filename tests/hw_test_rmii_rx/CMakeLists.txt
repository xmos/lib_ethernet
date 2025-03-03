cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(hw_test_rmii)

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

add_custom_target(xscope_cmds_enum_gen_rx DEPENDS ${XSCOPE_CMDS_ENUM_FILE})

set(COMPILER_FLAGS_COMMON   -g
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -Os
                            -Wno-reinterpret-alignment
                            -fxscope
                            -DBOARD_SUPPORT_BOARD=XK_ETH_XU316_DUAL_100M
                            -DENABLE_MAC_START_NOTIFICATION=1
                            )

foreach(phy PHY0 PHY1) # compile for each phy
    string(TOLOWER ${phy} phy_lower)
    set(APP_COMPILER_FLAGS_rx_${phy_lower}                 ${COMPILER_FLAGS_COMMON} -DUSE_${phy}=1)
    set(APP_COMPILER_FLAGS_rx_multiple_queues_${phy_lower}      ${COMPILER_FLAGS_COMMON} -DMULTIPLE_QUEUES=1 -DETHERNET_SUPPORT_HP_QUEUES=1 -DUSE_${phy}=1)
endforeach()

set(APP_XSCOPE_SRCS src/config.xscope)

set(APP_INCLUDES src/xscope_control src/xu316_dual_100m_ports ${REL_AUTOGEN_DIR})

set(XMOS_SANDBOX_DIR    ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()

foreach(target ${APP_BUILD_TARGETS})
    add_dependencies(${target} xscope_cmds_enum_gen_rx)
endforeach()
