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
from hw_helpers import log_ifg_summary
import pytest
from contextlib import nullcontext
import time
from xcore_app_control import XcoreAppControl
from socket_host import SocketHost
import re
import subprocess
import platform
import struct
from collections import defaultdict

pkg_dir = Path(__file__).parent

def log_timestamps_probed_from_dut(probe_ts, ifg_summary_filename, ifg_full_filename):
    overhead = 8 + 4 # preamble + crc
    timestamps_and_packet_len = []
    # Convert from bytes to uint32 words
    for i in range(0, len(probe_ts), 4):
        t = (probe_ts[i+3] << 24) | (probe_ts[i+2] << 16) | (probe_ts[i+1] << 8) | probe_ts[i]
        timestamps_and_packet_len.append(t)

    # Deinterleave timestamps and packet lengths
    timestamps = timestamps_and_packet_len[0::2]
    lengths = timestamps_and_packet_len[1::2]
    iters = min(len(lengths), len(timestamps))
    ifg_full_dict = defaultdict(list)
    errors = False
    for i in range(iters - 1):
        ts_diff = (timestamps[i+1] - timestamps[i]) % (1 << 32)
        packet_length = lengths[i] + overhead
        packet_time_ns = (1e9 * 8*packet_length)/line_speed
        ts_diff_ns = ts_diff * 10 # ref timer is 10ns
        ifg = ts_diff_ns - packet_time_ns
        if ifg < 96.0:
            errors = True
        ifg_full_dict[lengths[i]].append(round(ifg, 2))

    #print(ifg_full_dict)
    log_ifg_summary(ifg_full_dict,
                    ifg_summary_file=Path(ifg_summary_filename),
                    ifg_full_file=Path(ifg_full_filename))

    assert errors == False, f"Errors: Min IFG violation seen. Check {ifg_summary_filename} and {ifg_full_filename} for more details"



# When transmitting, get the DUT to either sweep through all packet sizes or send packets of one size.
# When fixed_size, the packet size is hardcoded in the test and can be changed (by changing 'packet_len' in the test code)
# when reqd to test for another size.
# This is largely for debug so not parametrizing for different sizes
@pytest.mark.debugger
@pytest.mark.parametrize("packet_type", ["sweep", "fixed_size"])
@pytest.mark.parametrize("dut_timestamp_probe", [True, False], ids=["ts_probe_on", "ts_probe_off"]) # Enable or disable timestamp probing in the DUT
def test_hw_tx_ifg(request, dut_timestamp_probe, packet_type):
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    phy = request.config.getoption("--phy")

    host_mac_address_str = "d0:d1:d2:d3:d4:d5" # debugger doesn't care about this but DUT does and we can filter using this to get only DUT packets

    test_duration_s = 30 # hardcoded. this is the duration in which we expect the DUT to complete sending all the packets

    verbose = False
    seed = 0
    rand = random.Random()
    rand.seed(seed)

    # Create pesky file names
    if packet_type == "sweep":
        pkt_sz_str = "sweep"
    else:
        pkt_sz_str = "fixed"

    if dut_timestamp_probe:
        probe_str = "probe"
    else:
        probe_str = "no_probe"

    # host generates IFG files both for probe on DUT enabled and disabled
    # DUT generates IFG files only when probes are enabled on the DUT
    ifg_summary_file_host = f"ifg_{pkt_sz_str}_summary_host_{probe_str}_{phy}.txt"
    ifg_full_file_host = f"ifg_{pkt_sz_str}_full_host_{probe_str}_{phy}.txt"

    ifg_summary_file_device = f"ifg_{pkt_sz_str}_summary_device_{probe_str}_{phy}.txt"
    ifg_full_file_device = f"ifg_{pkt_sz_str}_full_device_{probe_str}_{phy}.txt"

    print(f"ifg_summary_file_host = {ifg_summary_file_host}")
    print(f"ifg_full_file_host = {ifg_full_file_host}")

    print(f"ifg_summary_file_device = {ifg_summary_file_device}")
    print(f"ifg_full_file_device = {ifg_full_file_device}")

    dut_mac_address_str_lp = "00:01:02:03:04:05"
    dut_mac_address_lp = int(dut_mac_address_str_lp.replace(":", ""), 16)
    print(f"dut_mac_address_lp = 0x{dut_mac_address_lp:012x}")

    lp_client_id = 0

    if not dut_timestamp_probe:
        xe_name = pkg_dir / "hw_test_rmii_tx" / "bin" / f"tx_single_client_{phy}" / f"hw_test_rmii_tx_single_client_{phy}.xe"
    else:
        xe_name = pkg_dir / "hw_test_rmii_tx" / "bin" / f"tx_single_client_with_ts_probe_{phy}" / f"hw_test_rmii_tx_single_client_with_ts_probe_{phy}.xe"

    with XcoreAppControl(adapter_id, xe_name, verbose=verbose) as xcoreapp, hw_eth_debugger() as dbg:
        if dbg.wait_for_links_up():
            print("Links up")

        print("Wait for DUT to be ready")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()
        # config contents of Tx packets
        xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(lp_client_id, dut_mac_address_str_lp)
        xcoreapp.xscope_host.xscope_controller_cmd_set_host_macaddr(host_mac_address_str)

        dbg.capture_start()

        # connect to the dut and set up a consumer for the "tx_start_timestamp" (see config.xscope) probe. don't disconnect
        xcoreapp.xscope_host.xscope_controller_start_timestamp_recorder()

        # Since the endpoint created in xscope_controller_start_timestamp_recorder() is already connected
        if packet_type == "sweep":
            # Get DUT to sweep through all frame sizes
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_sweep(lp_client_id, connect=False)
            print(f"DUT sending packets sweeping through all packet sizes\n")
        else:
            # Get DUT to send packets with a fixed packet length
            packet_len = 60
            num_packets = 1005 # Atleast a 1000 since if timestamp probing enabled in the device, it puts out blocks of 1000 timestamps at a time over xscope
            xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(0, num_packets, packet_len, connect=False)
            print(f"DUT sending {num_packets} packets of size {packet_len} bytes\n")

        time.sleep(test_duration_s + 1)
        packets = dbg.capture_stop()

        # This will disconnect the endpoint that was connected in xscope_controller_start_timestamp_recorder(), and return all values
        # received on the "tx_start_timestamp" probe as a list of bytes
        probe_timestamps = xcoreapp.xscope_host.xscope_controller_stop_timestamp_recorder()

        # If received TX timestamps from the device, summarise those in a set of files
        if len(probe_timestamps):
            log_timestamps_probed_from_dut(probe_timestamps, ifg_summary_file_device, ifg_full_file_device)


        filtered_packets = [pkt for pkt in packets if Ether in pkt and pkt[Ether].dst == host_mac_address_str]
        packet_summary = rdpcap_to_packet_summary(filtered_packets)
        errors, _, _, ifg_dict = parse_packet_summary(  packet_summary,
                                                                0,
                                                                0,
                                                                dut_mac_address_lp,
                                                                verbose = True,
                                                                check_ifg = True,
                                                                log_ifg_per_payload_len=True)

        # Summarise the IFGs logged on the host. Write in different files based on whether the timestamps probing
        # was enabled or not in the DUT.
        if len(ifg_dict):
            log_ifg_summary(ifg_dict,
                            ifg_summary_file=Path(ifg_summary_file_host),
                            ifg_full_file=Path(ifg_full_file_host))

        print("Retrive status and shutdown DUT")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()

    if errors:
        assert False, f"Various errors reported!!\n{errors}\n\nDUT stdout = {stdout}"
    else:
        print("TEST PASS")
