set(LIB_NAME                lib_ethernet)

set(LIB_VERSION             3.5.0)

set(LIB_INCLUDES            api
                            src)

set(LIB_DEPENDENT_MODULES   "lib_locks(2.3.1)"
                            "lib_logging(3.3.1)"
                            "lib_xassert(4.3.1)"
                            # The following are pending XCCM support
                            # "lib_otpinfo(2.1.0)"
                            # "lib_gpio(1.1.0)"
                            # "lib_slicekit_support(2.0.1)"
                            )

set(LIB_COMPILER_FLAGS      -g
                            -O3
                            -mno-dual-issue)

set(LIB_OPTIONAL_HEADERS    ethernet_conf.h)

set(LIB_COMPILER_FLAGS_mii_master.xc        ${LIB_COMPILER_FLAGS} -O3 -fschedule -g0 -mno-dual-issue)
set(LIB_COMPILER_FLAGS_macaddr_filter.xc    ${LIB_COMPILER_FLAGS} -Wno-reinterpret-alignment)
set(LIB_COMPILER_FLAGS_mii.xc               ${LIB_COMPILER_FLAGS} -Wno-cast-align)
set(LIB_COMPILER_FLAGS_mii_ethernet_mac.xc  ${LIB_COMPILER_FLAGS} -Wno-cast-align)
set(LIB_COMPILER_FLAGS_ethernet.xc          ${LIB_COMPILER_FLAGS} -Wno-cast-align)

message(STATUS XMOS_SANDBOX_DIR: ${XMOS_SANDBOX_DIR})

# Fetch non-XCCM modules and add manually
include(FetchContent)
message(STATUS lib_gpio: ${XMOS_SANDBOX_DIR}lib_gpio)

if(NOT EXISTS "${XMOS_SANDBOX_DIR}lib_gpio")
    FetchContent_Declare(
        lib_gpio
        GIT_REPOSITORY git@github.com:xmos/lib_gpio
        GIT_TAG master
        SOURCE_DIR ${XMOS_SANDBOX_DIR}lib_gpio
    )
    message(STATUS POO)
    FetchContent_Populate(lib_gpio)
    message(STATUS WEE)
endif()

# if(NOT EXISTS "${XMOS_SANDBOX_DIR}lib_slicekit_support")
#     FetchContent_Declare(
#         lib_slicekit_support
#         GIT_REPOSITORY git@github.com:xmos/lib_slicekit_support
#         # GIT_TAG master
#         SOURCE_DIR "${XMOS_SANDBOX_DIR}/lib_slicekit_support"
#     )
#     FetchContent_Populate(lib_slicekit_support)
# endif()

# if(NOT EXISTS "${XMOS_SANDBOX_DIR}lib_otp_info")
#     FetchContent_Declare(
#         lib_otpinfo
#         GIT_REPOSITORY git@github.com:xmos/lib_otpinfo
#         # GIT_TAG master
#         SOURCE_DIR "${XMOS_SANDBOX_DIR}/lib_otpinfo"
#     )
#     FetchContent_Populate(lib_otpinfo)
# endif()

# Now add srcs and includes to app src
file(GLOB_RECURSE SOURCES_XC RELATIVE       ${XMOS_SANDBOX_DIR}/lib_ethernet/lib_ethernet "${XMOS_SANDBOX_DIR}/lib_ethernet/lib_ethernet/src/*.xc")
file(GLOB_RECURSE SOURCES_ASM RELATIVE      ${XMOS_SANDBOX_DIR}/lib_ethernet/lib_ethernet "${XMOS_SANDBOX_DIR}/lib_ethernet/lib_ethernet/src/*.S")
file(GLOB_RECURSE OTP_XC_SRCS RELATIVE      ${XMOS_SANDBOX_DIR}/lib_otpinfo/lib_otpinfo "${XMOS_SANDBOX_DIR}/lib_otpinfo/lib_otpinfo/src/*.xc")
file(GLOB_RECURSE GPIO_XC_SRCS RELATIVE     ${XMOS_SANDBOX_DIR}/lib_gpio/lib_gpio "${XMOS_SANDBOX_DIR}/lib_gpio/lib_gpio/src/*.xc")
file(GLOB_RECURSE SK_BS_S_SRCS RELATIVE     ${XMOS_SANDBOX_DIR}/lib_slicekit_support/lib_slicekit_support "${XMOS_SANDBOX_DIR}/lib_slicekit_support/lib_slicekit_support/src/SLICEKIT-L16/*.S")
set(LIB_XC_SRCS                             ${SOURCES_XC}
                                            ../../lib_otpinfo/lib_otpinfo/${OTP_XC_SRCS}
                                            ../../lib_gpio/lib_gpio/${GPIO_XC_SRCS})
set(LIB_ASM_SRCS                            ${SOURCES_ASM}
                                            ../../lib_slicekit_support/lib_slicekit_support/${SK_BS_S_SRCS})

list(APPEND LIB_INCLUDES    ../../lib_otpinfo/lib_otpinfo/api
                            ../../lib_gpio/lib_gpio/api
                            ../../lib_slicekit_support/lib_slicekit_support/api)

XMOS_REGISTER_MODULE()
