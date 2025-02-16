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
from xcore_app_control import XcoreAppControl, SocketHost
from xcore_app_control import scapy_send_l2_pkts_loop, scapy_send_l2_pkt_sequence
import re
import subprocess
import platform


pkg_dir = Path(__file__).parent


@pytest.mark.parametrize('send_method', ['socket'])
def test_hw_mii_restart(request, send_method):
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"


    verbose = False
    seed = 0
    rand = random.Random()
    rand.seed(seed)
    test_duration_s = 1.0
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
        socket_host = SocketHost(eth_intf, host_mac_address_str, dut_mac_address_str)
    else:
        assert False, f"Invalid send_method {send_method}"


    xe_name = pkg_dir / "hw_test_mii" / "bin" / "loopback" / "hw_test_mii_loopback.xe"
    with XcoreAppControl(adapter_id, xe_name, attach="xscope_app") as xcoreapp:
        print("Wait for DUT to be ready")
        stdout, stderr = xcoreapp.xscope_controller_cmd_connect()
        if verbose:
            print(stderr)


        print("Set DUT Mac address")
        stdout, stderr = xcoreapp.xscope_controller_cmd_set_dut_macaddr(0, dut_mac_address_str)
        if verbose:
            print(f"stdout = {stdout}")
            print(f"stderr = {stderr}")

        if send_method == "socket":
            num_packets_sent, host_received_packets = socket_host.send_recv(test_duration_s)
            assert host_received_packets == num_packets_sent, f"ERROR: Host received back fewer than it sent. Sent {num_packets_sent}, received back {host_received_packets}"

        for _ in range(num_restarts):
            # restart the mac
            print("Restart DUT Mac")
            stdout, stderr = xcoreapp.xscope_controller_cmd_restart_dut_mac()
            if verbose:
                print(f"stdout = {stdout}")
                print(f"stderr = {stderr}")

            # wait to connect again
            print("Connect to the DUT again")
            stdout, stderr = xcoreapp.xscope_controller_cmd_connect()
            if verbose:
                print(stderr)

            if send_method == "socket":
                num_packets_sent, host_received_packets = socket_host.send_recv(test_duration_s)
                # TODO When actually testing RMII restart, at this point, host should receive back 0 packets since the MAC has restarted and there are no mac address filters set.
                #assert host_received_packets == 0
                assert host_received_packets == num_packets_sent, f"ERROR: Host received back fewer than it sent. Sent {num_packets_sent}, received back {host_received_packets}"

            stdout, stderr = xcoreapp.xscope_controller_cmd_set_dut_macaddr(0, dut_mac_address_str)

            # Now the RX client should receive packets
            if send_method == "socket":
                num_packets_sent, host_received_packets = socket_host.send_recv(test_duration_s)
                #assert host_received_packets == num_packets_sent, f"ERROR: Host received back fewer than it sent. Sent {num_packets_sent}, received back {host_received_packets}"



        print("Retrive status and shutdown DUT")
        stdout, stderr = xcoreapp.xscope_controller_cmd_shutdown()

        if verbose:
            print(stderr)
        print("Terminating!!!")


