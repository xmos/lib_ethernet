cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(lib_ethernet_tests)

add_subdirectory(test_tx)
add_subdirectory(test_rx)
add_subdirectory(test_link_status)
add_subdirectory(test_appdata)
add_subdirectory(test_avb_traffic)
add_subdirectory(test_etype_filter)
add_subdirectory(test_rx_backpressure)
add_subdirectory(test_shaper)
add_subdirectory(test_time_rx)
add_subdirectory(test_timestamp_tx)
# add_subdirectory(test_time_rx_tx) # This test is built in pytest as we autogen the seed include file at runtime
add_subdirectory(test_time_tx)
add_subdirectory(test_vlan_strip)
add_subdirectory(test_speed_change)
add_subdirectory(test_rx_queues)
add_subdirectory(test_check_ifg_wait)
add_subdirectory(test_rmii_timing)
add_subdirectory(test_rmii_restart)
add_subdirectory(test_smi)
add_subdirectory(test_do_idle_slope_unit)
add_subdirectory(test_tx_ifg)

# HW test apps
add_subdirectory(hw_test_rmii_rx)
add_subdirectory(hw_test_rmii_tx)
add_subdirectory(hw_test_rmii_loopback)


