# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
from hw_helpers import get_mac_address, hw_eth_debugger, analyse_dbg_cap_vs_sent_miipackets
from helpers import create_expect, create_if_needed
from xcore_app_control import XcoreAppControl
from mii_packet import MiiPacket
from mii_clock import Clock
import pytest
import sys
from test_4_1_2 import do_test
from test_hw_mii_rx_only import test_hw_mii_rx_only as hw_mii_rx_only
import Pyxsim as px
import platform
import subprocess
import time
from pathlib import Path


def do_rx_test(mac, arch, packets_to_send):
    testname = "test_hw_4_1_2_rmii"
    line_speed = 100e6
    pkg_dir = Path(__file__).parent
    send_method = "debugger"

    adapter_id = requests.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    verbose = False

    dut_mac_address_str = "00:01:02:03:04:05"
    print(f"dut_mac_address = {dut_mac_address_str}")
    dut_mac_address = [int(i, 16) for i in dut_mac_address_str.split(":")]


    if send_method == "debugger":
        assert platform.system() in ["Linux"], f"HW debugger only supported on Linux"
        dbg = hw_eth_debugger()
    else:
        assert False, f"Invalid send_method {send_method}"


    xe_name = pkg_dir / "hw_test_mii" / "bin" / "loopback" / "hw_test_mii_loopback.xe"
    with XcoreAppControl(adapter_id, xe_name, attach="xscope_app", verbose=verbose) as xcoreapp:
        print("Wait for DUT to be ready")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()

        print("Set DUT Mac address")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(0, dut_mac_address_str)

        if send_method == "debugger":
            if dbg.wait_for_links_up():
                print("Links up")
            else:
                raise RuntimeError("Links not up")
            dbg.capture_start("packets_received.pcapng")
            
            print("Debugger sending packets")
            time_to_send = 0
            for packet_to_send in packets_to_send:
                dbg.inject_MiiPacket(dbg.debugger_phy_to_dut, packet_to_send)
            time.sleep(0.1) # Allow last packet to depart before stopping capture. 0.01s normally plenty but add margin

            received_packets = dbg.capture_stop()

        print("Retrive status and shutdown DUT")
        xcoreapp.xscope_host.xscope_controller_cmd_shutdown()
        print("Terminating!!!")

    # Analyse and compare against expected
    report = analyse_dbg_cap_vs_sent_miipackets(received_packets, packets_to_send, swap_src_dst=True) # Packets are looped back so swap MAC addresses for filter
    expect_folder = create_if_needed("expect_temp")
    expect_filename = f'{expect_folder}/{testname}.expect'
    create_expect(packets_to_send, expect_filename)
    tester = px.testers.ComparisonTester(open(expect_filename))
    
    assert tester.run(report.split("\n")[:-1]) # Need to chop off last line


def test_4_1_2_hw_debugger(request):
    from types import SimpleNamespace
    global requests
    requests = request
    random.seed(12)
    seed = random.randint(0, sys.maxsize)
    phy = SimpleNamespace(get_name=lambda: "rmii",
                          get_clock=lambda: SimpleNamespace(get_bit_time=lambda: 1))
    clock = SimpleNamespace(get_rate=Clock.CLK_50MHz,
                            get_min_ifg=lambda: 96)
    do_test(None, "rt_hp", "xs3", clock, phy, clock, phy, seed, hw_debugger_test=do_rx_test)
