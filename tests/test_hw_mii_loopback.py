from scapy.all import *
import threading
from pathlib import Path
import random
import copy
from mii_packet import MiiPacket
from hardware_test_tools.XcoreApp import XcoreApp
import pytest


pkg_dir = Path(__file__).parent

def send_l2_pkts(intf, packets):
    # Convert to scapy Ether frames
    frames = []
    for packet in packets:
        byte_data = bytes(packet.data_bytes)
        frame = Ether(dst=packet.dst_mac_addr_str, src=packet.src_mac_addr_str, type=packet.ether_len_type)/Raw(load=byte_data)
        frames.append(frame)

    # Send over ethernet
    sendp(frames, iface=intf, verbose=False)

recvd_packet_count = 0 # TODO find a better way than using globals
recvd_bytes = 0
def sniff_pkt(intf, expected_packets):
    def packet_callback(packet, expect_packets):
        global recvd_packet_count
        global recvd_bytes
        if Ether in packet and packet[Ether].dst == expect_packets[0].dst_mac_addr_str:
            payload = packet[Raw].load
            expected_payload = bytes(expect_packets[recvd_packet_count].data_bytes)
            if payload != expected_payload:
                print(f"ERROR: mismatch in pkt number {recvd_packet_count}")
                print(f"Received: {payload}")
                print(f"Expected: {expected_payload}")
                assert(False)
            #print("Received ", packet.summary(), len(payload), "packet ", recvd_packet_count)  # Print a summary of each packet
            recvd_packet_count += 1
            recvd_bytes += len(payload)

    sniff(iface=intf, prn=lambda pkt: packet_callback(pkt, expected_packets), timeout=5)

    print(f"Received {recvd_packet_count} looped back packets, {recvd_bytes} bytes")


@pytest.mark.parametrize('payload_len', ['max'])
def test_hw_mii_loopback(request, payload_len):
    global recvd_packet_count
    global recvd_bytes

    recvd_packet_count = 0
    recvd_bytes = 0

    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    seed = 0
    rand = random.Random()
    rand.seed(seed)

    test_duration_s = 0.1
    ethertype = 0x2222
    num_packets = 0
    src_mac_address = [0xdc, 0xa6, 0x32, 0xca, 0xe0, 0x20]

    loop_back_packets = []
    packets = []
    current_test_duration = 0

    # Create packets
    mac_address = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05]
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

    with XcoreApp(xe_name, adapter_id, attach="xscope") as xcore_app:
        thread_send = threading.Thread(target=send_l2_pkts, args=[eth_intf, packets])
        thread_sniff = threading.Thread(target=sniff_pkt, args=[eth_intf, loop_back_packets])

        thread_sniff.start()
        thread_send.start()
        thread_send.join()
        thread_sniff.join()

        assert(recvd_packet_count == num_packets), f"Error: {num_packets} sent but only {recvd_packet_count} looped back"


if __name__ == "__main__":
    test_hw_mii_loopback()
