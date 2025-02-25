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

def test_hw_mii_tx_sweep(request):
    print()
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    dbg = hw_eth_debugger()
    host_mac_address_str = "d0:d1:d2:d3:d4:d5" # debugger doesn't care about this but DUT does and we can filter using this to get only DUT packets

    test_duration_s = 30 # hardcoded. this is the duration in which we expect the DUT to complete sending all the packets

    # HP packet configuration
    hp_packet_len = 0
    hp_packet_bandwidth_bps = 0

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

    xe_name = pkg_dir / "hw_test_mii_tx" / "bin" / "hw_test_mii_tx_only.xe"
    with XcoreAppControl(adapter_id, xe_name, attach="xscope_app", verbose=verbose) as xcoreapp:
        if dbg.wait_for_links_up():
            print("Links up")

        print("Wait for DUT to be ready")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()
        # config contents of Tx packets
        xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(lp_client_id, dut_mac_address_str_lp)
        xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(hp_client_id, dut_mac_address_str_hp)
        xcoreapp.xscope_host.xscope_controller_cmd_set_host_macaddr(host_mac_address_str)

        dbg.capture_start()

        stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(hp_client_id, hp_packet_bandwidth_bps, hp_packet_len)
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_sweep(lp_client_id)
        print(f"DUT sending packets sweeping through all packet sizes\n")

        time.sleep(test_duration_s + 1)
        packets = dbg.capture_stop()
        filtered_packets = [pkt for pkt in packets if Ether in pkt and pkt[Ether].dst == host_mac_address_str]
        packet_summary = rdpcap_to_packet_summary(filtered_packets)
        errors, num_lp_received, num_hp_received = parse_packet_summary(  packet_summary,
                                                        0,
                                                        0,
                                                        dut_mac_address_lp,
                                                        expected_packet_len_hp = hp_packet_len,
                                                        dut_mac_address_hp = dut_mac_address_hp,
                                                        expected_bandwidth_hp = hp_packet_bandwidth_bps,
                                                        verbose = True,
                                                        check_ifg = True,
                                                        log_ifg_per_payload_len=True)

        print("Retrive status and shutdown DUT")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()

    if errors:
        assert False, f"Various errors reported!!\n{errors}\n\nDUT stdout = {stdout}"
    else:
        print("TEST PASS")
