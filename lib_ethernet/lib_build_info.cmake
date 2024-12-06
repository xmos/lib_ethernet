set(LIB_NAME                lib_ethernet)

set(LIB_VERSION             4.0.0)

set(LIB_INCLUDES            api
                            src)

set(LIB_DEPENDENT_MODULES   "lib_locks(2.3.1)"
                            "lib_logging(3.3.1)"
                            "lib_xassert(4.3.1)")

set(LIB_COMPILER_FLAGS      -g
                            -O3
                            -mno-dual-issue)

set(LIB_OPTIONAL_HEADERS    ethernet_conf.h)

set(LIB_COMPILER_FLAGS_mii_master.xc            ${LIB_COMPILER_FLAGS} -O3 -fschedule -g0 -mno-dual-issue)
set(LIB_COMPILER_FLAGS_macaddr_filter.xc        ${LIB_COMPILER_FLAGS} -Wno-reinterpret-alignment)
set(LIB_COMPILER_FLAGS_mii.xc                   ${LIB_COMPILER_FLAGS} -Wno-cast-align -Wno-unusual-code)
set(LIB_COMPILER_FLAGS_mii_ethernet_mac.xc      ${LIB_COMPILER_FLAGS} -Wno-cast-align -Wno-unusual-code)
set(LIB_COMPILER_FLAGS_mii_ethernet_rt_mac.xc   ${LIB_COMPILER_FLAGS} -Wno-unusual-code)
set(LIB_COMPILER_FLAGS_rgmii_buffering.xc       ${LIB_COMPILER_FLAGS} -Wno-unusual-code)
set(LIB_COMPILER_FLAGS_rgmii_ethernet_mac.xc    ${LIB_COMPILER_FLAGS} -Wno-unusual-code)
set(LIB_COMPILER_FLAGS_ethernet.xc              ${LIB_COMPILER_FLAGS} -Wno-cast-align)
set(LIB_COMPILER_FLAGS_rmii_ethernet_rt_mac.xc  ${LIB_COMPILER_FLAGS} -Wno-unusual-code)
set(LIB_COMPILER_FLAGS_rmii_master.xc           ${LIB_COMPILER_FLAGS} -mdual-issue)
# set(LIB_COMPILER_FLAGS_rmii_master.xc           ${LIB_COMPILER_FLAGS} -mno-dual-issue)


XMOS_REGISTER_MODULE()
