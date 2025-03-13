# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
from scapy.all import *
from pathlib import Path
from hw_helpers import get_mac_address, hw_eth_debugger
import pytest
from xcore_app_control import XcoreAppControl
from socket_host import SocketHost
import re
import platform


pkg_dir = Path(__file__).parent

recvd_packet_count = 0 # TODO find a better way than using globals
def sniff_pkt(intf, target_mac_addr, timeout_s, seq_ids):
    def packet_callback(packet):
        global recvd_packet_count
        if Ether in packet and packet[Ether].dst == target_mac_addr:
            """
            payload = packet[Raw].load
            seq_id = 0
            seq_id |= (int(payload[0]) << 24)
            seq_id |= (int(payload[1]) << 16)
            seq_id |= (int(payload[2]) << 8)
            seq_id |= (int(payload[3]) << 0)
            seq_ids.append(seq_id)
            """
            recvd_packet_count += 1

    sniff(iface=intf, prn=lambda pkt: packet_callback(pkt), timeout=timeout_s)
    print(f"Sniffer receieved {recvd_packet_count} packets on ethernet interface {intf}")


@pytest.mark.parametrize('send_method', ['socket'])
def test_hw_loopback(request, send_method):
    """
    Test that the device can loopback packets over an ethernet interface.

    The test application on the device is a loopback application that has a an LP RX client and a HP TX client running.
    Everything received on the RX interfaces if looped back out of the TX interface

    This is tested with only the host socket based way of testing, where the linux host opens
    raw sockets to send/receive traffic to/from the device.

    Note: Only 'max' (1514 bytes) size packets are used for this test since the device buffers cannot keep up with receiving small size
    packets with min IFG while also looping them back.
    """
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    no_debugger = request.config.getoption("--no-debugger")

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    phy = request.config.getoption("--phy")

    test_duration_s = request.config.getoption("--test-duration")
    if not test_duration_s:
        test_duration_s = 0.4
    test_duration_s = float(test_duration_s)

    verbose = False

    payload_len = 'max'

    host_mac_address_str = get_mac_address(eth_intf)
    assert host_mac_address_str, f"get_mac_address() couldn't find mac address for interface {eth_intf}"
    print(f"host_mac_address = {host_mac_address_str}")

    dut_mac_address_str = "00:11:22:33:44:55"
    print(f"dut_mac_address = {dut_mac_address_str}")


    host_mac_address = [int(i, 16) for i in host_mac_address_str.split(":")]
    dut_mac_address = [int(i, 16) for i in dut_mac_address_str.split(":")]


    num_packets_sent = 0

    print(f"Going to test {test_duration_s} seconds of packets")

    if send_method == "socket":
        assert platform.system() in ["Linux"], f"Sending using sockets only supported on Linux"
        socket_host = SocketHost(eth_intf, host_mac_address_str, dut_mac_address_str, verbose=verbose)
    else:
        assert False, f"Invalid send_method {send_method}"


    xe_name = pkg_dir / "hw_test_rmii_loopback" / "bin" / f"loopback_{phy}" / f"hw_test_rmii_loopback_{phy}.xe"
    with XcoreAppControl(adapter_id, xe_name, verbose=verbose) as xcoreapp, hw_eth_debugger() as dbg:
        print("Wait for DUT to be ready")
        if not no_debugger:
            if dbg.wait_for_links_up():
                print("Links up")

        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()

        print("Set DUT Mac address")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(0, dut_mac_address_str)

        if send_method == "socket":
            num_packets_sent, host_received_packets = socket_host.send_recv(test_duration_s)

        print("Retrive status and shutdown DUT")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()

        print("Terminating!!!")


    errors = []
    if host_received_packets != num_packets_sent:
        errors.append(f"ERROR: Host received back fewer than it sent. Sent {num_packets_sent}, received back {host_received_packets}")

    # Check for any seq id mismatch errors reported by the DUT
    matches = re.findall(r"^DUT ERROR:.*", stdout, re.MULTILINE)
    if matches:
        errors.append(f"ERROR: DUT logs report errors.")
        for m in matches:
            errors.append(m)

    client_index = 0
    m = re.search(fr"DUT client index {client_index}: Received (\d+) bytes, (\d+) packets", stdout)
    if not m or len(m.groups()) < 2:
        errors.append(f"ERROR: DUT does not report received bytes and packets")
    else:
        bytes_received, dut_received_packets = map(int, m.groups())
        if int(dut_received_packets) != num_packets_sent:
            errors.append(f"ERROR: Packets dropped during DUT receive. Host sent {num_packets_sent}, DUT Received {dut_received_packets}")

    if len(errors):
        error_msg = "\n".join(errors)
        assert False, f"Various errors reported!!\n{error_msg}\n\nDUT stdout = {stdout}"



