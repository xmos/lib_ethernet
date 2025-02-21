# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
import copy
from types import SimpleNamespace
from hw_helpers import mii2pcapfile, get_mac_address, calc_time_diff, hw_eth_debugger
from hardware_test_tools.XcoreApp import XcoreApp
from mii_clock import Clock
from mii_packet import MiiPacket
import pytest
import sys
from test_4_1_2 import do_test
from test_hw_mii_rx_only import test_hw_mii_rx_only as hw_mii_rx_only


requests = None # So we don't have to pass this through do_test

def do_rx_test(mac, arch, packets_to_send):
    pcapfile_send_file = "packets_sent.pcapng"
    mii2pcapfile(packets_to_send, pcapfile_send_file)
    payload_len = ['max', 'min', 'random'][0]
    # hw_mii_rx_only(requests, 'debugger', payload_len)

    ###############################################
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
    from socket_host import SocketHost, scapy_send_l2_pkts_loop, scapy_send_l2_pkt_sequence
    import re
    import subprocess
    import platform

    pkg_dir = Path(__file__).parent
    send_method = "debugger"

    request = requests
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    test_duration_s = request.config.getoption("--test-duration")
    if not test_duration_s:
        test_duration_s = 0.4
    test_duration_s = float(test_duration_s)

    verbose = False
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


    if send_method == "debugger":
        assert platform.system() in ["Linux"], f"Sending using sockets only supported on Linux"
        # we are sending on the debugger, receiving on the host
        socket_host = SocketHost(eth_intf, host_mac_address_str, dut_mac_address_str, verbose=verbose)
        dbg = hw_eth_debugger()
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

        if send_method == "debugger":
            if dbg.wait_for_links_up():
                print("Links up")
            else:
                raise RuntimeError("Links not up")
            dbg.capture_start("packets_received.pcapng")
            #num_packets_sent = socket_host.send(test_duration_s, payload_len=payload_len)
            
            packet_idx = 0
            for packet_to_send in packets_to_send:
                print(packet_to_send)
                nibbles = packet_to_send.get_nibbles()
                if len(nibbles) % 2 != 0:
                    print(f"Warning: padding packet {packet_idx} by{len(nibbles)} nibbles to {len(nibbles)+1} due to debugger inject limitations")
                    nibbles.append(0)
                byte_list = [(nibbles[i + 1] << 4) | nibbles[i] for i in range(0, len(nibbles), 2)]
                hex_string = bytes(byte_list).hex()
                dbg.inject_packets(dbg.debugger_phy_to_dut, data=hex_string, append_preamble_crc=False)
                packet_idx += 1

            # print(packets_to_send)
            # dbg.inject_packets(phy_to_dut, filename=pcapfile_send_file)
            received_packets = dbg.capture_stop()

        print("Retrive status and shutdown DUT")

        time.sleep(0.1) # To allow all packets to be sent out of the debugger before terminating the xcore app. TODO
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()
        print(stdout)
        print("Terminating!!!")



def test_4_1_2_hw_debugger(request):
    if False:
       
        pckt = MiiPacket(random.Random(),
                dst_mac_addr=[1,2,3,4,5,6],
                create_data_args=['step', (0, 150)],
                inter_frame_gap=10)
        print(pckt.dump())
        nibbles = pckt.get_nibbles()
        byte_list = [(nibbles[i + 1] << 4) | nibbles[i] for i in range(0, len(nibbles), 2)]
        hex_string = bytes(byte_list).hex()
        print(hex_string)
    else:
        global requests
        requests = request
        random.seed(12)
        seed = random.randint(0, sys.maxsize)
        phy = SimpleNamespace(get_name=lambda: "rmii",
                              get_clock=lambda: SimpleNamespace(get_bit_time=lambda: 1))
        clock = SimpleNamespace(get_rate=Clock.CLK_50MHz,
                                get_min_ifg=lambda: 1e9)
        do_test(None, "rt_hp", "xs3", clock, phy, clock, phy, seed, hw_debugger_test=do_rx_test)
