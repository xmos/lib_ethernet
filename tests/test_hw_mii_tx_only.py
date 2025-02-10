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


def load_packet_file(filename):
    chunk_size = 6 + 6 + 2 + 4 + 4
    structures = []
    with open(filename, 'rb') as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break

            dst = int.from_bytes(chunk[:6], byteorder='big')
            src = int.from_bytes(chunk[6:12], byteorder='big')
            etype = int.from_bytes(chunk[12:14], byteorder='big')
            seqid = int.from_bytes(chunk[14:18], byteorder='little')
            length = int.from_bytes(chunk[18:22], byteorder='little')
            structures.append([dst, src, etype, seqid, length])

    return structures

def parse_packet_summary(packet_summary, expect_count, expected_packet_len):
    errors = ""
    expected_seqid = 0
    for packet in packet_summary:
        seqid = packet[3]
        length = packet[4]
        if length != expected_packet_len:
            errors += f"Incorrect length at seqid: {seqid}, expected: {expected_packet_len} got: {length}\n"
        if seqid != expected_seqid:
            errors += f"Missing seqid: {expected_seqid}, got: {seqid}\n"
            expected_seqid = seqid
        expected_seqid += 1

    if expected_seqid != expect_count:
        errors += f"Did not get {expect_count} packets, got only {len(packet_summary)}"

    return errors if errors != "" else None

@pytest.mark.parametrize('send_method', ['scapy', 'socket'])
def test_hw_mii_tx_only(request, send_method):
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    test_duration_s = request.config.getoption("--test-duration")
    if not test_duration_s:
        test_duration_s = 0.4
    test_duration_s = float(test_duration_s)

    test_type = "seq_id"
    verbose = False
    seed = 0
    rand = random.Random()
    rand.seed(seed)


    host_mac_address_str = get_mac_address(eth_intf)
    assert host_mac_address_str, f"get_mac_address() couldn't find mac address for interface {eth_intf}"
    print(f"host_mac_address = {host_mac_address_str}")

    dut_mac_address_str = "00:01:02:03:04:05"
    print(f"dut_mac_address = {dut_mac_address_str}")


    host_mac_address = [int(i, 16) for i in host_mac_address_str.split(":")]
    dut_mac_address = [int(i, 16) for i in dut_mac_address_str.split(":")]

    capture_file = "packets.bin"
   
    xe_name = pkg_dir / "hw_test_mii_tx" / "bin" / "hw_test_mii_tx_only.xe"
    xcoreapp = XcoreAppControl(adapter_id, xe_name, attach="xscope_app")
    xcoreapp.__enter__()

    print("Wait for DUT to be ready")
    stdout, stderr = xcoreapp.xscope_controller_cmd_connect()
    #extract DUT details from stderr
    regex = r".*DUT preparing to send (\d+) packets of length (\d+).*"
    match = re.search(regex, stderr)
    if match:
        expected_packet_count = int(match.groups()[0])
        expected_packet_len = int(match.groups()[1])
    else:
        assert 0, f"could not find {regex} in {stderr}"

    if verbose:
        print(stderr)

    print("Starting sniffer")
    if send_method == "scapy":
        send_time = []
        seq_ids = []
        thread_sniff = threading.Thread(target=sniff_pkt, args=[eth_intf, dut_mac_address_str, test_duration_s+5, seq_ids, capture_file])

        thread_sniff.start()
        # now signal to DUT that we are ready to receive
        stdout, stderr = xcoreapp.xscope_controller_cmd_set_host_ready_to_receive()
        print(f"DUT stdout ready to rx: {stdout} {stderr}")

        thread_sniff.join()

        print(f"Time taken by sendp() = {send_time[0]:.6f}s when sending {test_duration_s}s worth of packets")

        sleep_time = 0
        if send_time[0] < test_duration_s: # sendp() is faster than real time on my Mac :((
            sleep_time += (test_duration_s - send_time[0]) + 1
        print(f"host recvd seq ids {seq_ids}")
        host_received_packets = recvd_packet_count
    if send_method == "socket":
        assert platform.system() in ["Linux"], f"Receiving using sockets only supported on Linux"
        socket_host = SocketHost(eth_intf, host_mac_address_str, dut_mac_address_str)
        # now signal to DUT that we are ready to receive
        stdout, stderr = xcoreapp.xscope_controller_cmd_set_host_ready_to_receive()
        print(f"DUT stdout post ready to rx: {stdout} {stderr}")
        host_received_packets = socket_host.recv(capture_file)
        print(f"Received packets: {host_received_packets}")

    print("Retrive status and shutdown DUT")

    xcoreapp.terminate()
    # for some reason standard shutdown is not happy above 50k packets
    # stdout, stderr = xcoreapp.xscope_controller_cmd_shutdown()

    packet_summary = load_packet_file(capture_file)
    errors = parse_packet_summary(packet_summary, expected_packet_count, expected_packet_len)

    # print(f"DUT stdout post: {stdout} {stderr}")

    if errors:
        assert False, f"Various errors reported!!\n{errors}\n\nDUT stdout = {stderr}"
    else:
        print("TEST PASS")

# For local testing only
if __name__ == "__main__":
    packet_summary = load_packet_file("packets.bin")
    print(parse_packet_summary(packet_summary, 100, 1514))
