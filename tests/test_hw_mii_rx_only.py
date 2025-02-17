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
@pytest.mark.parametrize('payload_len', ['max', 'min', 'random'])
def test_hw_mii_rx_only(request, send_method, payload_len):
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    test_duration_s = request.config.getoption("--test-duration")
    if not test_duration_s:
        test_duration_s = 0.4
    test_duration_s = float(test_duration_s)

    verbose = True
    seed = 0
    rand = random.Random()
    rand.seed(seed)

    host_mac_address_str = get_mac_address(eth_intf)
    assert host_mac_address_str, f"get_mac_address() couldn't find mac address for interface {eth_intf}"
    print(f"host_mac_address = {host_mac_address_str}")

    dut_mac_address_str = "10:11:12:13:14:15"
    print(f"dut_mac_address = {dut_mac_address_str}")


    host_mac_address = [int(i, 16) for i in host_mac_address_str.split(":")]
    dut_mac_address = [int(i, 16) for i in dut_mac_address_str.split(":")]

    ethertype = [0x22, 0x22]
    num_packets_sent = 0
    packets = []


    # Create packets
    print(f"Going to test {test_duration_s} seconds of packets")

    if send_method == "scapy":
        if payload_len == 'max':
            num_data_bytes = 1500
        elif payload_len == 'min':
            num_data_bytes = 46
        elif payload_len == 'random':
            num_data_bytes = random.randint(46, 1500)
        else:
            assert False
        packet_duration_bits = (14 + num_data_bytes + 4)*8 + 64 + 96 # Assume Min IFG
        test_duration_bits = test_duration_s * 100e6
        num_packets_sent = int(float(test_duration_bits)/packet_duration_bits)
        test_type = "no_seq_id"
        packet = MiiPacket(rand,
                        dst_mac_addr=dut_mac_address,
                        src_mac_addr=host_mac_address,
                        ether_len_type = ethertype,
                        num_data_bytes=num_data_bytes,
                        create_data_args=['same', (0, num_data_bytes)],
                        )
        if test_type == 'seq_id':
            packets = []
            for i in range(num_packets_sent): # Update sequence IDs in payload
                packet_copy = copy.deepcopy(packet)
                packet_copy.data_bytes[0] = (i >> 24) & 0xff
                packet_copy.data_bytes[1] = (i >> 16) & 0xff
                packet_copy.data_bytes[2] = (i >> 8) & 0xff
                packet_copy.data_bytes[3] = (i >> 0) & 0xff
                packets.append(packet_copy)
    elif send_method == "socket":
        assert platform.system() in ["Linux"], f"Sending using sockets only supported on Linux"
        socket_host = SocketHost(eth_intf, host_mac_address_str, dut_mac_address_str, verbose=verbose)
    else:
        assert False, f"Invalid send_method {send_method}"


    xe_name = pkg_dir / "hw_test_mii" / "bin" / "rx_only" / "hw_test_mii_rx_only.xe"
    with XcoreAppControl(adapter_id, xe_name, attach="xscope_app", verbose=verbose) as xcoreapp:
        print("Wait for DUT to be ready")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()

        print("Set DUT Mac address")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(0, dut_mac_address_str)


        print(f"Send {test_duration_s} seconds of packets now")
        send_time = []

        if send_method == "scapy":
            if test_type == 'seq_id':
                thread_send = threading.Thread(target=scapy_send_l2_pkt_sequence, args=[eth_intf, packets, send_time]) # send a packet sequence
            else:
                thread_send = threading.Thread(target=scapy_send_l2_pkts_loop, args=[eth_intf, packet, num_packets_sent, send_time]) # send the same packet in a loop

            thread_send.start()
            thread_send.join()

            print(f"Time taken by sendp() = {send_time[0]:.6f}s when sending {test_duration_s}s worth of packets")

            sleep_time = 0
            if send_time[0] < test_duration_s: # sendp() is faster than real time on my Mac :((
                sleep_time += (test_duration_s - send_time[0])

            time.sleep(sleep_time + 10) # Add an extra 10s of buffer
        elif send_method == "socket":
            num_packets_sent = socket_host.send(test_duration_s, payload_len=payload_len)

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

    client_index = 0
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





