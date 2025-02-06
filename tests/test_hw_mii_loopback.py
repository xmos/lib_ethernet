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
import re
import subprocess
import platform


pkg_dir = Path(__file__).parent

"""
def send_l2_pkts(intf, packets):
    frames = mii2scapy(packets)
    # Send over ethernet
    sendp(frames, iface=intf, verbose=False)

recvd_packet_count = 0 # TODO find a better way than using globals
recvd_bytes = 0
def sniff_pkt(intf, expected_packets, timeout_s):
    def packet_callback(packet, expect_packets):
        global recvd_packet_count
        global recvd_bytes
        if Ether in packet and packet[Ether].dst == expect_packets[0].dst_mac_addr_str:
            payload = packet[Raw].load
            expected_payload = bytes(expect_packets[recvd_packet_count].data_bytes)

            if payload != expected_payload:
                print(f"ERROR: mismatch in pkt number {recvd_packet_count}")
                #print(f"Received: {payload}")
                #print(f"Expected: {expected_payload}")
                #assert(False)

            #print("Received ", packet.summary(), len(payload), "packet ", recvd_packet_count)  # Print a summary of each packet
            recvd_packet_count += 1
            recvd_bytes += len(payload)

    sniff(iface=intf, prn=lambda pkt: packet_callback(pkt, expected_packets), timeout=timeout_s)

    print(f"Received {recvd_packet_count} looped back packets, {recvd_bytes} bytes")


@pytest.mark.parametrize('payload_len', ['max'])
def test_hw_mii_loopback(request, payload_len):
    global recvd_packet_count
    global recvd_bytes

    recvd_packet_count = 0
    recvd_bytes = 0

    adapter_id = request.config.getoption("--adapter-id")
    #assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    seed = 0
    rand = random.Random()
    rand.seed(seed)

    if adapter_id == None:
        test_duration_s = 4.0 # xrun in a different terminal. Test is more stable (TODO), so test longer duration
    else:
        test_duration_s = 0.1

    ethertype = [0x22, 0x22]
    num_packets = 0
    src_mac_address = [0xdc, 0xa6, 0x32, 0xca, 0xe0, 0x20]

    loop_back_packets = []
    packets = []
    current_test_duration = 0

    # Create packets
    mac_address = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05]

    print(f"Generating {test_duration_s} seconds of packet sequence")

    while True:
        if payload_len == 'max':
            num_data_bytes = 1500
        elif payload_len == 'random':
            num_data_bytes = random.randint(46, 1500)
        else:
            assert False

        packets.append(MiiPacket(rand,
            dst_mac_addr=mac_address,
            src_mac_addr=src_mac_address,
            ether_len_type = ethertype,
            num_data_bytes=num_data_bytes
            ))
        packet = copy.deepcopy(packets[-1])
        tmp = packet.dst_mac_addr
        packet.dst_mac_addr = packet.src_mac_addr
        packet.src_mac_addr = tmp
        loop_back_packets.append(packet)

        num_packets += 1
        packet_duration_bits = (14 + num_data_bytes + 4)*8 # Ignore IFG
        packet_duration_s = packet_duration_bits / float(100e6)
        current_test_duration += packet_duration_s
        if current_test_duration > test_duration_s:
            break

    print(f"Going to test {num_packets} packets")
    xe_name = pkg_dir / "hw_test_mii_loopback" / "bin" / "hw_test_mii_loopback.xe"

    context_manager = XcoreApp(xe_name, adapter_id, attach="xscope") if adapter_id is not None else nullcontext()

    with context_manager as xcore_app:
        thread_send = threading.Thread(target=send_l2_pkts, args=[eth_intf, packets])
        thread_sniff = threading.Thread(target=sniff_pkt, args=[eth_intf, loop_back_packets, test_duration_s+5])

        thread_sniff.start()
        thread_send.start()
        thread_send.join()
        thread_sniff.join()

        assert(recvd_packet_count == num_packets), f"Error: {num_packets} sent but only {recvd_packet_count} looped back"
"""

@pytest.mark.parametrize('send_method', ['socket'])
def test_hw_mii_loopback(request, send_method):
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

    payload_len = 'max'

    host_mac_address_str = get_mac_address(eth_intf)
    assert host_mac_address_str, f"get_mac_address() couldn't find mac address for interface {eth_intf}"
    print(f"host_mac_address = {host_mac_address_str}")

    dut_mac_address_str = "00:01:02:03:04:05"
    print(f"dut_mac_address = {dut_mac_address_str}")


    host_mac_address = [int(i, 16) for i in host_mac_address_str.split(":")]
    dut_mac_address = [int(i, 16) for i in dut_mac_address_str.split(":")]

    ethertype = [0x22, 0x22]
    num_packets = 0
    packets = []


    # Create packets
    print(f"Generating {test_duration_s} seconds of packet sequence")

    if payload_len == 'max':
        num_data_bytes = 1500
    elif payload_len == 'random':
        num_data_bytes = random.randint(46, 1500)
    else:
        assert False

    packet_duration_bits = (14 + num_data_bytes + 4)*8 + 64 + 96 # Assume Min IFG

    test_duration_bits = test_duration_s * 100e6
    num_packets = int(float(test_duration_bits)/packet_duration_bits)
    print(f"Going to test {num_packets} packets")

    if send_method == "socket":
        assert platform.system() in ["Linux"], f"Sending using sockets only supported on Linux"
        socket_host = SocketHost(eth_intf, host_mac_address_str, dut_mac_address_str)
    else:
        assert False, f"Invalid send_method {send_method}"


    xe_name = pkg_dir / "hw_test_mii" / "bin" / "loopback" / "hw_test_mii_loopback.xe"
    xcoreapp = XcoreAppControl(adapter_id, xe_name, attach="xscope_app")
    xcoreapp.__enter__()

    print("Wait for DUT to be ready")
    stdout, stderr = xcoreapp.xscope_controller_cmd_connect()

    if verbose:
        print(stderr)

    print(f"Send {num_packets} packets now")
    send_time = []

    if send_method == "socket":
        host_received_packets = socket_host.send_recv(num_packets)

    print("Retrive status and shutdown DUT")
    stdout, stderr = xcoreapp.xscope_controller_cmd_shutdown()

    if verbose:
        print(stderr)

    print("Terminating!!!")
    xcoreapp.terminate()

    errors = []
    if host_received_packets != num_packets:
        errors.append(f"ERROR: Host received back fewer than it sent. Sent {num_packets}, received back {host_received_packets}")

    # Check for any seq id mismatch errors reported by the DUT
    matches = re.findall(r"^DUT ERROR:.*", stderr, re.MULTILINE)
    if matches:
        errors.append(f"ERROR: DUT logs report errors.")
        for m in matches:
            errors.append(m)

    m = re.search(r"DUT: Received (\d+) bytes, (\d+) packets", stderr)
    if not m or len(m.groups()) < 2:
        errors.append(f"ERROR: DUT does not report received bytes and packets")
    else:
        bytes_received, dut_received_packets = map(int, m.groups())
        if int(dut_received_packets) != num_packets:
            errors.append(f"ERROR: Packets dropped during DUT receive. Host sent {num_packets}, DUT Received {dut_received_packets}")

    if len(errors):
        error_msg = "\n".join(errors)
        assert False, f"Various errors reported!!\n{error_msg}\n\nDUT stdout = {stderr}"



