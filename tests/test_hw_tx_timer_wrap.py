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
from hw_helpers import load_packet_file
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
"""
Time it takes for the socket receiver to get ready to receive a packet.
After starting the socket receiver process, wait this long before asking the DUT to transmit
"""

def recv_packet_from_dut(socket_host, xcoreapp, lp_client_id, hp_client_id, verbose):
    expected_packet_len = 1500
    capture_file = "packets.bin"
    socket_host.recv_asynch_start(capture_file)
    # now signal to DUT that we are ready to receive and say what we want from it
    stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(hp_client_id, 0, 0) # no tx hp
    stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(lp_client_id, 1, expected_packet_len)

    host_received_packets = socket_host.recv_asynch_wait_complete()
    if verbose:
        print(f"Host Received packets: {host_received_packets}")
    """
    Socket receiver times out after 5s of inactivity. So just receiving a packet at this point indicates that the dut didn't have a > 5s latency in sending
    """
    assert(host_received_packets == 1)
    packet_summary = load_packet_file(capture_file)
    return packet_summary[0][5], packet_summary[0][6]

@pytest.mark.parametrize('send_method', ['socket'])
def test_hw_tx_timer_wrap(request, send_method):
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    phy = request.config.getoption("--phy")

    no_debugger = request.config.getoption("--no-debugger")

    verbose = False
    seed = 0
    rand = random.Random()
    rand.seed(seed)


    host_mac_address_str = get_mac_address(eth_intf)
    assert host_mac_address_str, f"get_mac_address() couldn't find mac address for interface {eth_intf}"
    print(f"host_mac_address = {host_mac_address_str}")

    dut_mac_address_str_lp = "00:01:02:03:04:05"
    dut_mac_address_str_hp = "f0:f1:f2:f3:f4:f5"
    print(f"dut_mac_address_lp = {dut_mac_address_str_lp}")
    print(f"dut_mac_address_hp = {dut_mac_address_str_hp}")

    host_mac_address = [int(i, 16) for i in host_mac_address_str.split(":")]
    dut_mac_address_lp = [int(i, 16) for i in dut_mac_address_str_lp.split(":")]
    dut_mac_addres_hp= [int(i, 16) for i in dut_mac_address_str_hp.split(":")]

    xe_name = pkg_dir / "hw_test_rmii_tx" / "bin" / f"tx_{phy}" / f"hw_test_rmii_tx_{phy}.xe"
    print(f"Asking DUT to send the first packet")

    nanoseconds_in_a_second = 1000000000
    packet_recv_times = []
    wait_times_s = [] # Artificially introduced wait between 2 packets sent by the DUT
    with XcoreAppControl(adapter_id, xe_name, verbose=verbose) as xcoreapp, hw_eth_debugger() as dbg:
        print("Wait for DUT to be ready")
        if not no_debugger:
            if dbg.wait_for_links_up():
                print("Links up")

        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()

        # config contents of Tx packets
        lp_client_id = 0
        hp_client_id = 1
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(lp_client_id, dut_mac_address_str_lp)
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(hp_client_id, dut_mac_address_str_hp)
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_host_macaddr(host_mac_address_str)

        print("Starting sniffer")
        if send_method == "socket":
            assert platform.system() in ["Linux"], f"Receiving using sockets only supported on Linux"
            socket_host = SocketHost(eth_intf, host_mac_address_str, f"{dut_mac_address_str_lp} {dut_mac_address_str_hp}", verbose=verbose)

            tv_sec, tv_nsec = recv_packet_from_dut(socket_host, xcoreapp, lp_client_id, hp_client_id, verbose)
            packet_recv_times.append((tv_sec, tv_nsec))
            if verbose:
                print(f"recv time = {packet_recv_times[-1][0] + (packet_recv_times[-1][1]*nanoseconds_in_a_second)} ns")

            # Do a long wait ensuring timer wraparound.
            # Wait for a random number of seconds between 20 and 40 seconds
            wait_times_s.append(rand.randint(20, 40))
            if verbose:
                print(f"wait_time = {wait_times_s[-1]} s")
            time.sleep(wait_times_s[-1])

            tv_sec, tv_nsec = recv_packet_from_dut(socket_host, xcoreapp, lp_client_id, hp_client_id, verbose)
            packet_recv_times.append((tv_sec, tv_nsec))
            if verbose:
                print(f"recv time = {packet_recv_times[-1][0] + (packet_recv_times[-1][1]*nanoseconds_in_a_second)} ns")

            # Do a long wait ensuring timer wraparound
            wait_times_s.append(rand.randint(20, 40))
            if verbose:
                print(f"wait_time = {wait_times_s[-1]} s")
            time.sleep(wait_times_s[-1])

            tv_sec, tv_nsec = recv_packet_from_dut(socket_host, xcoreapp, lp_client_id, hp_client_id, verbose)
            packet_recv_times.append((tv_sec, tv_nsec))
            if verbose:
                print(f"recv time = {packet_recv_times[-1][0] + (packet_recv_times[-1][1]*nanoseconds_in_a_second)} ns")

            # Do a long wait ensuring timer wraparound
            wait_times_s.append(rand.randint(20, 40))
            if verbose:
                print(f"wait_time = {wait_times_s[-1]} s")
            time.sleep(wait_times_s[-1])

            tv_sec, tv_nsec = recv_packet_from_dut(socket_host, xcoreapp, lp_client_id, hp_client_id, verbose)
            packet_recv_times.append((tv_sec, tv_nsec))
            if verbose:
                print(f"recv time = {packet_recv_times[-1][0] + (packet_recv_times[-1][1]*nanoseconds_in_a_second)} ns")

            print("Retrive status and shutdown DUT")
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()

        for i in range(len(packet_recv_times) - 1):
            # Check recv time diff for consecutive packets
            packet_receive_time_diff_ns = calc_time_diff(packet_recv_times[i][0], packet_recv_times[i][1], packet_recv_times[i+1][0], packet_recv_times[i+1][1])

            """
            Adding 5 + 1 seconds to the interpacket wait time that was introduced between packets
            5s is the inactivity time after receiving a packet that the socket recv waits for before exiting.
            1s for the overhead of CMD_HOST_SET_DUT_TX_PACKETS cmd to both clients + socket receiver setup time
            """
            wait_time_ns = (wait_times_s[i] + 5 + 1) * nanoseconds_in_a_second
            diff = packet_receive_time_diff_ns - wait_time_ns
            print(f"packet_receive_time_diff_ns = {packet_receive_time_diff_ns}, wait_time_ns = {wait_time_ns}")
            print(f"diff = {diff}")
            # Allow 1s of extra delay
            assert diff < nanoseconds_in_a_second, f"DUT inter packet delay later than expected. Delay between received packets {packet_receive_time_diff_ns/nanoseconds_in_a_second : .4f}, Expected delay {wait_time_ns/nanoseconds_in_a_second : .4f} "
