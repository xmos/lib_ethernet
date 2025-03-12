# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
from scapy.all import *
import threading
from pathlib import Path
import random
import copy
from mii_packet import MiiPacket
from hardware_test_tools.XcoreApp import XcoreApp
from hw_helpers import mii2scapy, scapy2mii, get_mac_address, calc_time_diff, hw_eth_debugger
from hw_helpers import load_packet_file, rdpcap_to_packet_summary, parse_packet_summary
from hw_helpers import packet_overhead, line_speed
import pytest
from contextlib import nullcontext
import time
from xcore_app_control import XcoreAppControl
from socket_host import SocketHost
import re
import subprocess
import platform
import struct

pkg_dir = Path(__file__).parent

@pytest.mark.debugger
def test_hw_hot_plug(request):
    """
    Simulate hot-plugging the device and test that it recovers after a hot-plug.

    hot plugging is simulated by power cycling the PHY on the HW debugger by writing to the power down bit in bmrc register
    over the mdio interface available on the debugger. This causes the ethernet link on the device to go down and then back up.

    In the test, the tx app on the device is configured to send packets and the device is hot plugged while transmitting.
    The test checks that there's packet loss due to the hot-plugging.
    After the link is back up, the device is configured to transmit again and the test checks that there's no packet loss
    this time.
    The above sequence is repeated 'num_hot_plug_instances' times

    """
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    phy = request.config.getoption("--phy")

    host_mac_address_str = "d0:d1:d2:d3:d4:d5" # debugger doesn't care about this but DUT does and we can filter using this to get only DUT packets

    test_duration_s = 5 # hardcoded small duration since we hot plug the device and test multiple times
    num_hot_plug_instances = 5 # simulate hot plugging the device 5 times and check that it can still transmit after each hot plug

    # HP packet configuration
    hp_packet_len = 0
    hp_packet_bandwidth_bps = 0

    # LP packet configuration
    expected_packet_len_lp = 1514
    bits_per_packet = 8 * (expected_packet_len_lp + packet_overhead)
    total_bits = line_speed * test_duration_s
    total_bits *= (line_speed - hp_packet_bandwidth_bps) / line_speed # Subtract expected HP bandwidth
    expected_packet_count = int(total_bits / bits_per_packet)

    print(f"Setting DUT to send {expected_packet_count} LP packets of size {expected_packet_len_lp}")
    print(f"Setting DUT to send {hp_packet_bandwidth_bps} bps HP packets of size {hp_packet_len}")

    verbose = False
    seed = 0
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address_str_lp = "00:01:02:03:04:05"
    dut_mac_address_str_hp = "f0:f1:f2:f3:f4:f5"
    dut_mac_address_lp = int(dut_mac_address_str_lp.replace(":", ""), 16)
    dut_mac_address_hp = int(dut_mac_address_str_hp.replace(":", ""), 16)
    print(f"dut_mac_address_lp = 0x{dut_mac_address_lp:012x}")
    print(f"dut_mac_address_hp = 0x{dut_mac_address_hp:012x}")

    lp_client_id = 0
    hp_client_id = 1

    xe_name = pkg_dir / "hw_test_rmii_tx" / "bin" / f"tx_{phy}" / f"hw_test_rmii_tx_{phy}.xe"
    with XcoreAppControl(adapter_id, xe_name, verbose=verbose) as xcoreapp, hw_eth_debugger() as dbg:
        if dbg.wait_for_links_up():
            print("Links up")

        print("Wait for DUT to be ready")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()
        # config contents of Tx packets
        xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(lp_client_id, dut_mac_address_str_lp)
        xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(hp_client_id, dut_mac_address_str_hp)
        xcoreapp.xscope_host.xscope_controller_cmd_set_host_macaddr(host_mac_address_str)

        for iter in range(num_hot_plug_instances):
            dbg.capture_start()
            # now signal to DUT that we are ready to receive and say what we want from it
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(hp_client_id, hp_packet_bandwidth_bps, hp_packet_len)
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(lp_client_id, expected_packet_count, expected_packet_len_lp)

            print(f"DUT sending packets for {test_duration_s}s, with the phy link going down and up in between\n")

            # power cycle the PHY on the debugger that is connected to the DUT.
            # This causes the link on the DUT phy to go down (when the debugger PHY is powered off)
            start_time = time.time()  # Record the start time
            duration = test_duration_s  # Number of seconds to run
            # power cycle a few times
            while time.time() - start_time < duration:
                print("power cycle the PHY connected to the DUT")
                dbg.power_cycle_phy(dbg.debugger_phy_to_dut)
                time.sleep(rand.randint(1, 4))

            time.sleep(1)
            packets = dbg.capture_stop()

            # we need to filter because debugger captures both ports
            filtered_packets = [pkt for pkt in packets if Ether in pkt and pkt[Ether].dst == host_mac_address_str]
            packet_summary = rdpcap_to_packet_summary(filtered_packets)
            errors, num_lp_received, num_hp_received, _ = parse_packet_summary(  packet_summary,
                                                        expected_packet_count,
                                                        expected_packet_len_lp,
                                                        dut_mac_address_lp,
                                                        expected_packet_len_hp = hp_packet_len,
                                                        dut_mac_address_hp = dut_mac_address_hp,
                                                        expected_bandwidth_hp = hp_packet_bandwidth_bps,
                                                        verbose = True,
                                                        check_ifg = False)
            if not num_lp_received < expected_packet_count:
                errors += "Error: All LP packets received despite phy power cycles.\nPerhaps the PHY did not power cycle.\n"
                break

            print(f"\nDUT sending packets for {test_duration_s}s, with the phy link staying up in between\n")

            # get device to Transmit again, without power cycling the PHY this time
            dbg.wait_for_links_up()
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect() # Ensure that device can see link up
            dbg.capture_start()
            # now signal to DUT that we are ready to receive and say what we want from it
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(hp_client_id, hp_packet_bandwidth_bps, hp_packet_len)
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(lp_client_id, expected_packet_count, expected_packet_len_lp)
            time.sleep(test_duration_s + 1)
            packets = dbg.capture_stop()

            # we need to filter because debugger captures both ports
            filtered_packets = [pkt for pkt in packets if Ether in pkt and pkt[Ether].dst == host_mac_address_str]

            packet_summary = rdpcap_to_packet_summary(filtered_packets)
            errors, num_lp_received, num_hp_received, _ = parse_packet_summary(  packet_summary,
                                                        expected_packet_count,
                                                        expected_packet_len_lp,
                                                        dut_mac_address_lp,
                                                        expected_packet_len_hp = hp_packet_len,
                                                        dut_mac_address_hp = dut_mac_address_hp,
                                                        expected_bandwidth_hp = hp_packet_bandwidth_bps,
                                                        start_seq_id_lp = (2*iter + 1) * expected_packet_count,
                                                        verbose = True,
                                                        check_ifg = False)
            if errors: # If there are errors when no hotplug then break and fail the test
                break

        print("Retrive status and shutdown DUT")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()

    if errors:
        assert False, f"Various errors reported!!\n{errors}\n\nDUT stdout = {stdout}"
    else:
        print("TEST PASS")
