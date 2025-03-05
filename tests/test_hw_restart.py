# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
from scapy.all import *
import threading
from pathlib import Path
import random
import copy
from mii_packet import MiiPacket
from hardware_test_tools.XcoreApp import XcoreApp
from hw_helpers import mii2scapy, scapy2mii, get_mac_address
import pytest
from contextlib import nullcontext
import time
from xcore_app_control import XcoreAppControl
from socket_host import SocketHost
import re
import subprocess
import platform


pkg_dir = Path(__file__).parent

@pytest.mark.parametrize('send_method', ['socket'])
def test_hw_restart(request, send_method):
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    phy = request.config.getoption("--phy")

    verbose = False
    seed = 0
    rand = random.Random()
    rand.seed(seed)
    test_duration_s = 5.0
    payload_len = 'max'
    num_restarts = 4

    host_mac_address_str = get_mac_address(eth_intf)
    assert host_mac_address_str, f"get_mac_address() couldn't find mac address for interface {eth_intf}"
    print(f"host_mac_address = {host_mac_address_str}")

    dut_mac_address_str = "00:11:22:33:44:55"
    print(f"dut_mac_address = {dut_mac_address_str}")


    print(f"Going to test {test_duration_s} seconds of packets")

    if send_method == "socket":
        assert platform.system() in ["Linux"], f"Sending using sockets only supported on Linux"
        socket_host = SocketHost(eth_intf, host_mac_address_str, dut_mac_address_str, verbose=verbose)
    else:
        assert False, f"Invalid send_method {send_method}"


    xe_name = pkg_dir / "hw_test_rmii_loopback" / "bin" / f"loopback_{phy}" / f"hw_test_rmii_loopback_{phy}.xe"
    with XcoreAppControl(adapter_id, xe_name, verbose=verbose) as xcoreapp:
        print("Wait for DUT to be ready")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()

        print("Set DUT Mac address")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(0, dut_mac_address_str)

        if send_method == "socket":
            num_packets_sent, host_received_packets = socket_host.send_recv(test_duration_s)
            if host_received_packets != num_packets_sent:
                print(f"ERROR: Host received back fewer than it sent. Sent {num_packets_sent}, received back {host_received_packets}")
                stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()
                print("shutdown stdout:\n")
                print(stdout)
                assert False

        for _ in range(num_restarts):
            # restart the mac
            print("Restart DUT Mac")
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_restart_dut_mac()

            # wait to connect again
            print("Connect to the DUT again")
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()

            if send_method == "socket":
                num_packets_sent, host_received_packets = socket_host.send_recv(test_duration_s)
                if host_received_packets != 0:
                    print(f"After mac restart and before setting macaddr filters, host expected to receive 0 packets. Received {host_received_packets} packets instead")
                    stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()
                    print("shutdown stdout:\n")
                    print(stdout)
                    assert False

            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(0, dut_mac_address_str)

            # Now the RX client should receive packets
            if send_method == "socket":
                num_packets_sent, host_received_packets = socket_host.send_recv(test_duration_s)
                if host_received_packets != num_packets_sent:
                    print(f"ERROR: Host received back fewer than it sent. Sent {num_packets_sent}, received back {host_received_packets}")
                    stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()
                    print("shutdown stdout:\n")
                    print(stdout)
                    assert False

        print("Retrive status and shutdown DUT")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()

        print("Terminating!!!")


