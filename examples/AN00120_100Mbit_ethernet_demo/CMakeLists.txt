cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(AN00210_100Mbit_ethernet_demo)

set(APP_HW_TARGET           SLICEKIT-ETH-TRIANGLE1.xn)

set(APP_DEPENDENT_MODULES   lib_ethernet)
                            # lib_otp_info
                            # lib_gpio
                            # lib_slicekit_support)

set(APP_PCA_ENABLE ON)

set(COMILER_FLAGS_COMMON    -g
                            -report
                            -DDEBUG_PRINT_ENABLE
                            -save-temps
                            -Os
                            -Xmapper --map -Xmapper MAPFILE)

set(APP_COMPILER_FLAGS      ${COMPILER_FLAGS_COMMON})
set(APP_COMPILER_FLAGS_icmp ${COMPILER_FLAGS_COMMON}
                            -Wno-reinterpret-alignment)

set(APP_XSCOPE_SRCS src/config.xscope)

set(XMOS_SANDBOX_DIR    ${CMAKE_CURRENT_LIST_DIR}/../../..)

#Fetch non-XCCM modules
include(FetchContent)
set(XMOS_DEP_DIR_lib_gpio ${XMOS_SANDBOX_DIR}/lib_gpio)
if(NOT EXISTS ${XMOS_SANDBOX_DIR}/lib_gpio)
    FetchContent_Declare(
        lib_gpio
        GIT_REPOSITORY git@github.com:xmos/lib_gpio
        GIT_TAG develop
        SOURCE_DIR ${XMOS_DEP_DIR_lib_gpio}
    )
    FetchContent_Populate(lib_gpio)
endif()

set(XMOS_DEP_DIR_lib_slicekit_support ${XMOS_SANDBOX_DIR}/lib_slicekit_support)
if(NOT EXISTS ${XMOS_SANDBOX_DIR}/lib_slicekit_support)
    FetchContent_Declare(
        lib_slicekit_support
        GIT_REPOSITORY git@github.com:xmos/lib_slicekit_support
        GIT_TAG master
        SOURCE_DIR ${XMOS_DEP_DIR_lib_slicekit_support}
    )
    FetchContent_Populate(lib_slicekit_support)
endif()

set(XMOS_DEP_DIR_lib_otpinfo ${XMOS_SANDBOX_DIR}/lib_otpinfo)
if(NOT EXISTS ${XMOS_SANDBOX_DIR}/lib_otp_nfo)
    FetchContent_Declare(
        lib_otpinfo
        GIT_REPOSITORY git@github.com:xmos/lib_otpinfo
        GIT_TAG master
        SOURCE_DIR ${XMOS_DEP_DIR_lib_otpinfo}
    )
    FetchContent_Populate(lib_otpinfo)
endif()

# Now add srcs and includes to app src
file(GLOB_RECURSE SOURCES_XC RELATIVE           ${CMAKE_CURRENT_LIST_DIR} "src/*.xc")
file(GLOB_RECURSE OTP_XC_SRCS RELATIVE          ${CMAKE_CURRENT_LIST_DIR} "../../../lib_otpinfo/lib_otpinfo/src/*.xc")
file(GLOB_RECURSE GPIO_XC_SRCS RELATIVE         ${CMAKE_CURRENT_LIST_DIR} "../../../lib_gpio/lib_gpio/src/*.xc")
file(GLOB_RECURSE SK_BS_XC_SRCS RELATIVE        ${CMAKE_CURRENT_LIST_DIR} "../../../lib_slicekit_support/lib_slicekit_support/src/*.xc")
set(APP_XC_SRCS                                 ${SOURCES_XC}
                                                ${OTP_XC_SRCS}
                                                ${GPIO_XC_SRCS}
                                                ${SK_BS_XC_SRCS})

set(APP_INCLUDES            ${CMAKE_CURRENT_LIST_DIR}/src
                            ${XMOS_DEP_DIR_lib_otpinfo}/lib_otpinfo/api
                            ${XMOS_DEP_DIR_lib_gpio}/lib_gpio/api
                            ${XMOS_DEP_DIR_lib_slicekit_support}/lib_slicekit_support/api)

XMOS_REGISTER_APP()

