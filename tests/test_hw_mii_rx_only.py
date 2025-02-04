from scapy.all import *
import threading
from pathlib import Path
import random
import copy
from mii_packet import MiiPacket
from hardware_test_tools.XcoreApp import XcoreApp
from hw_helpers import mii2scapy, scapy2mii
import pytest
from contextlib import nullcontext
import time
from xcore_app_control import XcoreAppControl
import re
import subprocess


pkg_dir = Path(__file__).parent

# Send the same packet in a loop
def send_l2_pkts_loop(intf, packet, loop_count, time_container):
    frame = mii2scapy(packet)
    # Send over ethernet
    start = time.perf_counter()
    sendp(frame, iface=intf, count=loop_count, verbose=False, realtime=True)
    end = time.perf_counter()
    time_container.append(end-start)



def send_l2_pkt_sequence(intf, packets, time_container):
    frames = mii2scapy(packets)
    start = time.perf_counter()
    sendp(frames, iface=intf, verbose=False, realtime=True)
    end = time.perf_counter()
    time_container.append(end-start)





@pytest.mark.parametrize('send_method', ['scapy', 'socket'])
def test_hw_mii_rx_only(request, send_method):
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    test_duration_s = request.config.getoption("--test-duration")
    if not test_duration_s:
        test_duration_s = 0.4

    test_type = "seq_id"
    verbose = False
    seed = 0
    rand = random.Random()
    rand.seed(seed)

    payload_len = 'max'


    ethertype = [0x22, 0x22]
    num_packets = 0
    src_mac_address = [0xdc, 0xa6, 0x32, 0xca, 0xe0, 0x20]

    packets = []


    # Create packets
    mac_address = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05]

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

    if send_method == "scapy":
        packet = MiiPacket(rand,
                        dst_mac_addr=mac_address,
                        src_mac_addr=src_mac_address,
                        ether_len_type = ethertype,
                        num_data_bytes=num_data_bytes,
                        create_data_args=['same', (0, num_data_bytes)],
                        )
        if test_type == 'seq_id':
            packets = []
            for i in range(num_packets): # Update sequence IDs in payload
                packet_copy = copy.deepcopy(packet)
                packet_copy.data_bytes[0] = (i >> 24) & 0xff
                packet_copy.data_bytes[1] = (i >> 16) & 0xff
                packet_copy.data_bytes[2] = (i >> 8) & 0xff
                packet_copy.data_bytes[3] = (i >> 0) & 0xff
                packets.append(packet_copy)
    elif send_method == "socket":
        # build the af_packet_send utility
        socket_send_file = pkg_dir / "host" / "af_packet_send" / "af_packet_l2_send.c"
        assert socket_send_file.exists()
        ret = subprocess.run(["g++", "-o", "send_packets", socket_send_file, "-lpthread"],
                             capture_output = True,
                             text = True)
        assert ret.returncode == 0, (
            f"af_packet_send failed to compile"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )
        socket_send_app = pkg_dir / "host" / "af_packet_send" / "send_packets"
    else:
        assert False, f"Invalid send_method {send_method}"


    xe_name = pkg_dir / "hw_test_mii_rx_only" / "bin" / "hw_test_mii_rx_only.xe"
    xcoreapp = XcoreAppControl(adapter_id, xe_name, attach="xscope_app")
    xcoreapp.__enter__()

    print("Wait for DUT to be ready")
    stdout, stderr = xcoreapp.xscope_controller_cmd_connect()

    if verbose:
        print(stderr)

    print(f"Send {num_packets} packets now")
    send_time = []

    if send_method == "scapy":
        if test_type == 'seq_id':
            thread_send = threading.Thread(target=send_l2_pkt_sequence, args=[eth_intf, packets, send_time]) # send a packet sequence
        else:
            thread_send = threading.Thread(target=send_l2_pkts_loop, args=[eth_intf, packet, num_packets, send_time]) # send the same packet in a loop

        thread_send.start()
        thread_send.join()

        print(f"Time taken by sendp() = {send_time[0]:.6f}s when sending {test_duration_s}s worth of packets")

        sleep_time = 0
        if send_time[0] < test_duration_s: # sendp() is faster than real time on my Mac :((
            sleep_time += (test_duration_s - send_time[0])

        time.sleep(sleep_time + 10) # Add an extra 10s of buffer
    elif send_method == "socket":
        ret = subprocess.run([socket_send_app, eth_intf, num_packets],
                             capture_output = True,
                             text = True)
        assert ret.returncode == 0, (
            f"{socket_send_app} returned runtime error"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

    print("Retrive status and shutdown DUT")
    stdout, stderr = xcoreapp.xscope_controller_cmd_shutdown()

    if verbose:
        print(stderr)

    print("Terminating!!!")
    xcoreapp.terminate()

    errors = []

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
        bytes_received, packets_received = map(int, m.groups())
        if int(packets_received) != num_packets:
            errors.append(f"ERROR: Packets dropped. Sent {num_packets}, DUT Received {packets_received}")

    if len(errors):
        error_msg = "\n".join(errors)
        assert False, f"Various errors reported!!\n{error_msg}\n\nDUT stdout = {stderr}"





