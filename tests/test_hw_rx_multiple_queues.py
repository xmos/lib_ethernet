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
def test_hw_rx_multiple_queues(request, send_method):
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    phy = request.config.getoption("--phy")

    test_duration_s = request.config.getoption("--test-duration")
    if not test_duration_s:
        test_duration_s = 0.4
    test_duration_s = float(test_duration_s)

    verbose = False
    seed = 0
    rand = random.Random()
    rand.seed(seed)

    payload_len = 'max'

    host_mac_address_str = get_mac_address(eth_intf)
    assert host_mac_address_str, f"get_mac_address() couldn't find mac address for interface {eth_intf}"
    print(f"host_mac_address = {host_mac_address_str}")

    dut_mac_address_str = "10:11:12:13:14:15 12:34:56:78:9a:bc 11:33:55:77:88:00"
    print(f"dut_mac_address = {dut_mac_address_str}")

    dut_mac_addresses = []
    for m in dut_mac_address_str.split():
        dut_mac_address = [int(i, 16) for i in m.split(":")]
        dut_mac_addresses.append(dut_mac_address)

    print(f"dut_mac_addresses = {dut_mac_addresses}")

    num_packets_sent = 0
    # Create packets
    print(f"Going to test {test_duration_s} seconds of packets")

    if send_method == "socket":
        assert platform.system() in ["Linux"], f"Sending using sockets only supported on Linux"
        socket_host = SocketHost(eth_intf, host_mac_address_str, dut_mac_address_str, verbose=verbose)
    else:
        assert False, f"Invalid send_method {send_method}"


    xe_name = pkg_dir / "hw_test_rmii_rx" / "bin" / f"rx_multiple_queues_{phy}" / f"hw_test_rmii_rx_multiple_queues_{phy}.xe"
    with XcoreAppControl(adapter_id, xe_name, attach="xscope_app", verbose=verbose) as xcoreapp:
        print("Wait for DUT to be ready")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()

        print("Set DUT Mac address for each RX client")
        for i,m in enumerate(dut_mac_address_str.split()):
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(i, m)

        if send_method == "socket":
            # call non-blocking send so we can do the xscope_controller_cmd_set_dut_receive while sending packets
            socket_host.send_non_blocking(test_duration_s)
            stopped = [False, False] # The rx clients are receiving by default
            while socket_host.send_in_progress():
                client_index = rand.randint(0,1) # client 0 and 1 are LP so toggle receiving for one of them
                stopped[client_index] = stopped[client_index] ^ 1
                delay = rand.randint(1, 1000) * 0.0001 # Up to 100 ms wait before toggling 'stopped'
                time.sleep(delay)
                stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_receive(client_index, stopped[client_index])

        num_packets_sent = socket_host.num_packets_sent

        print("Retrive status and shutdown DUT")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()

        print("Terminating!!!")


    errors = []

    # Check for any seq id mismatch errors reported by the DUT
    matches = re.findall(r"^DUT ERROR:.*", stdout, re.MULTILINE)
    if matches:
        errors.append(f"ERROR: DUT logs report errors.")
        for m in matches:
            errors.append(m)

    client_index = 2 # We're interested in checking that the HP client (index 2) has received all the packets
    m = re.search(fr"DUT client index {client_index}: Received (\d+) bytes, (\d+) packets", stdout)

    if not m or len(m.groups()) < 2:
        errors.append(f"ERROR: DUT does not report received bytes and packets")
    else:
        bytes_received, packets_received = map(int, m.groups())
        if int(packets_received) != num_packets_sent:
            errors.append(f"ERROR: Packets dropped. Sent {num_packets_sent}, DUT Received {packets_received}")

    if len(errors):
        error_msg = "\n".join(errors)
        assert False, f"Various errors reported!!\n{error_msg}\n\nDUT stdout = {stdout}"





