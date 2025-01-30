from scapy.all import *
import threading
from pathlib import Path
import random
import copy
from mii_packet import MiiPacket
from hardware_test_tools.XcoreApp import XcoreApp
import pytest
from contextlib import nullcontext
import datetime
import time


pkg_dir = Path(__file__).parent

def send_l2_pkts(intf, packet, loop_count):
    # Convert to scapy Ether frames
    byte_data = bytes(packet.data_bytes)
    frame = Ether(dst=packet.dst_mac_addr_str, src=packet.src_mac_addr_str, type=packet.ether_len_type)/Raw(load=byte_data)

    # Send over ethernet
    sendp(frame, iface=intf, count=loop_count, verbose=False, realtime=True)
    #for i in range(loop_count):
    #    sendp(frame, iface=intf, verbose=False)
    time.sleep(10)




@pytest.mark.parametrize('payload_len', ['max'])
def test_hw_mii_rx_only(request, payload_len):
    adapter_id = request.config.getoption("--adapter-id")
    #assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    seed = 0
    rand = random.Random()
    rand.seed(seed)

    if adapter_id == None:
        test_duration_s = 1 # xrun in a different terminal. Test is more stable (TODO), so test longer duration
    else:
        test_duration_s = 0.1

    ethertype = 0x2222
    num_packets = 0
    src_mac_address = [0xdc, 0xa6, 0x32, 0xca, 0xe0, 0x20]

    loop_back_packets = []
    packets = []
    current_test_duration = 0

    # Create packets
    mac_address = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05]

    print(f"Generating {test_duration_s} seconds of packet sequence")

    if payload_len == 'max':
        num_data_bytes = 1500
    elif payload_len == 'random':
        num_data_bytes = random.randint(46, 1500)
    else:
        assert False

    packet = MiiPacket(rand,
                    dst_mac_addr=mac_address,
                    src_mac_addr=src_mac_address,
                    ether_len_type = ethertype,
                    num_data_bytes=num_data_bytes
                    )
    #packet_duration_bits = (14 + num_data_bytes + 4)*8 + 64 + 96 # Assume Min IFG
    packet_duration_bits = (num_data_bytes)*8 # Assume Min IFG

    test_duration_bits = test_duration_s * 100e6
    num_packets = int(float(test_duration_bits)/packet_duration_bits)

    print(f"Going to test {num_packets} packets")
    xe_name = pkg_dir / "hw_test_mii_rx_only" / "bin" / "hw_test_mii_rx_only.xe"

    context_manager = XcoreApp(xe_name, adapter_id, attach="xscope") if adapter_id is not None else nullcontext()

    with context_manager as xcore_app:
        thread_send = threading.Thread(target=send_l2_pkts, args=[eth_intf, packet, num_packets])

        thread_send.start()
        thread_send.join()

