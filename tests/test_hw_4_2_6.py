# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

"""
Send packets with less than min IFG to the DUT and see how smallest IFG for which the device still receives without dropping packets
"""

from hw_helpers import hw_4_1_x_test_init, line_speed, analyse_dbg_cap_vs_sent_miipackets
from helpers import create_if_needed, create_expect
from test_4_2_6 import do_test
from pathlib import Path
import platform
from hw_helpers import hw_eth_debugger
from xcore_app_control import XcoreAppControl
import Pyxsim as px
import time

# This requires a custom version because we want to test IFG and the hw debugger cannot do
# that with played packets as they are sent one by one. We need to instead use the inject command and manipulate ifg_bytes in the inject_packet method
def do_test_4_2_6_hw_dbg(request, testname, mac, arch, packets_to_send):
    testname += "_" + mac + "_" + arch
    pkg_dir = Path(__file__).parent
    send_method = "debugger"

    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    phy = request.config.getoption("--phy")

    verbose = False

    dut_mac_address_str = "00:01:02:03:04:05"
    print(f"dut_mac_address = {dut_mac_address_str}")
    dut_mac_address = [int(i, 16) for i in dut_mac_address_str.split(":")]

    if send_method == "debugger":
        assert platform.system() in ["Linux"], f"HW debugger only supported on Linux"
        dbg = hw_eth_debugger()
    else:
        assert False, f"Invalid send_method {send_method}"

    xe_name = pkg_dir / "hw_test_mii" / "bin" / f"loopback_{phy}" / f"hw_test_mii_loopback_{phy}.xe"
    print(xe_name)

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

            # Debugger can only set IFG in steps of 8b (a bytes)
            standard_ifg_bytes = 12 # 96 bit times
            min_tested_ifg_bytes = 9 # 72 bit times
            num_packets_to_send = 10 # The DUT takes longer to send than rx so don't overwhelm the Rx buffer

            for ifg_byte_count in range(standard_ifg_bytes, min_tested_ifg_bytes-1, -1):
                dbg.capture_start("packets_received.pcapng")
                time.sleep(0.25) # Ensure capture started
                packet = packets_to_send[0]
                print("Debugger sending packets")
                dbg.inject_MiiPacket(dbg.debugger_phy_to_dut, packet, num=num_packets_to_send, ifg_bytes=ifg_byte_count)
                sleep_time = (len(packet.get_nibbles()) * 4 + ifg_byte_count * 8) * num_packets_to_send / line_speed
                time.sleep(sleep_time + 0.1)

                received_packets = dbg.capture_stop(use_raw=True)

                # Analyse and compare against expected
                sent_packets = [packet for i in range(num_packets_to_send)]
                report = analyse_dbg_cap_vs_sent_miipackets(received_packets, sent_packets, swap_src_dst=True) # Packets are looped back so swap MAC addresses for filter
                print("****IFG BYTES ", ifg_byte_count, " PACKET BYTES ", len(packet.get_packet_bytes()) + 8 + 4)

                expect_folder = create_if_needed("expect_temp")
                expect_filename = f'{expect_folder}/{testname}.expect'
                create_expect([packet for i in range(num_packets_to_send)], expect_filename)
                tester = px.testers.ComparisonTester(open(expect_filename))

                assert tester.run(report.split("\n")[:-1]) # Need to chop off last line

        print("Retrive status and shutdown DUT")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()
        print("Terminating!!!")



def test_4_2_6_hw_debugger(request):
    seed, testname, mac, arch, phy, clock = hw_4_1_x_test_init(26)
    # This doesn't exercise min IFG times
    # do_test(None, mac, arch, clock, phy, clock, phy, seed, hw_debugger_test=(do_hw_dbg_rx_test, request, testname))
    do_test(None, mac, arch, clock, phy, clock, phy, seed, hw_debugger_test=(do_test_4_2_6_hw_dbg, request, testname))
