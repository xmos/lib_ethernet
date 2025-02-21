from scapy.all import *
import threading
from pathlib import Path
import random
import copy
from mii_packet import MiiPacket
from hardware_test_tools.XcoreApp import XcoreApp
from hw_helpers import mii2scapy, scapy2mii, get_mac_address, calc_time_diff, hw_eth_debugger
import pytest
from contextlib import nullcontext
import time
from xcore_app_control import XcoreAppControl
from socket_host import SocketHost
import re
import platform
import struct
from decimal import Decimal
import statistics


pkg_dir = Path(__file__).parent
packet_overhead = 8 + 4 + 12 # preamble, CRC and IFG
line_speed = 100e6

def load_packet_file(filename):
    chunk_size = 6 + 6 + 2 + 4 + 4 + 8 + 8
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
            time_s = int.from_bytes(chunk[22:30], byteorder='little')
            time_ns = int.from_bytes(chunk[30:38], byteorder='little')

            structures.append([dst, src, etype, seqid, length, time_s, time_ns])

    return structures

def rdpcap_to_packet_summary(packets):
    structures = []
    for packet in packets:
        raw_payload = bytes(packet.payload)
        dst = int.from_bytes(raw_payload[:6], byteorder='big')
        src = int.from_bytes(raw_payload[6:12], byteorder='big')
        etype = int.from_bytes(raw_payload[12:14], byteorder='big')
        seqid = int.from_bytes(raw_payload[14:18], byteorder='little')
        length = len(raw_payload)
        time_s, fraction = divmod(packet.time, 1)  # provided in 'Decimal' python format
        time_s = int(time_s)
        time_ns = int(fraction * Decimal('1e9'))

        structures.append([dst, src, etype, seqid, length, time_s, time_ns])

    return structures

def parse_packet_summary(packet_summary,
                        expected_count_lp,
                        expected_packet_len_lp,
                        dut_mac_address_lp,
                        expected_packet_len_hp = 0,
                        dut_mac_address_hp = 0,
                        expected_bandwidth_hp = 0,
                        verbose = False,
                        check_ifg = False):
    print("Parsing packet file")
    # get first packet time with valid source addr
    datum = 0
    for packet in packet_summary:
        if packet[1] == dut_mac_address_lp or packet[1] == dut_mac_address_hp:
            datum = int(packet[5] * 1e9 + packet[6])
            break

    errors = ""
    expected_seqid_lp = 0
    expected_seqid_hp = 0
    counted_lp = 0
    counted_hp = 0
    last_valid_packet_time = 0
    last_length = 0 # We need this for checking IFG
    ifgs = []

    for packet in packet_summary:
        dst = packet[0]
        src = packet[1]
        seqid = packet[3]
        length = packet[4]
        tv_s = packet[5]
        tv_ns = packet[6]
        packet_time = int(tv_s * 1e9 + tv_ns) - datum

        if src == dut_mac_address_lp:
            if length != expected_packet_len_lp:
                errors += f"Incorrect LP length at seqid: {seqid}, expected: {expected_packet_len_lp} got: {length}\n"
            if seqid != expected_seqid_lp:
                errors += f"Missing LP seqid: {expected_seqid_lp}, got: {seqid}\n"
                expected_seqid_lp = seqid
            expected_seqid_lp += 1
            counted_lp += 1

        if src == dut_mac_address_hp:
            if length != expected_packet_len_hp:
                errors += f"Incorrect HP length at seqid: {seqid}, expected: {expected_packet_len_hp} got: {length}\n"
            if seqid != expected_seqid_hp:
                errors += f"Missing HP seqid: {expected_seqid_hp}, got: {seqid}\n"
                expected_seqid_hp = seqid
            expected_seqid_hp += 1
            counted_hp += 1

        if src == dut_mac_address_lp or src == dut_mac_address_hp:
            if check_ifg:
                packet_time_diff_ns = packet_time - last_valid_packet_time
                packet_time_ns = 1e9 / line_speed * 8 * (last_length + 4 + 8) #preamble and CRC only
                ifg_ns = packet_time_diff_ns - packet_time_ns
                ifgs.append(ifg_ns)
            # ensure we only count valid packets for bandwidth calc
            last_valid_packet_time = packet_time
            last_length = length


    if expected_bandwidth_hp:
        total_time_ns = last_valid_packet_time # Last packet time
        num_bits_hp = counted_hp * (expected_packet_len_hp + packet_overhead) * 8
        bits_per_second = num_bits_hp / (total_time_ns / 1e9)
        difference_pc = abs(expected_bandwidth_hp - bits_per_second) / abs(expected_bandwidth_hp) * 100
        allowed_tolerance_pc = 0.1 # How close HP bandwidth should be for test pass in %
        text = f"Calculated HP thoughput: {bits_per_second:.1f}, expected throughput: {expected_bandwidth_hp:.1f}, diff: {difference_pc:.2f}% (max: {allowed_tolerance_pc:.2f}%)"
        if difference_pc > allowed_tolerance_pc:
            errors += text
        if verbose:
            print(text)

    if check_ifg:
        ifgs = ifgs[1:-10] # The first is always wrong as is the datum and last few are HP dominared with gaps as LP tx shuts down first
        min_ifg = min(ifgs)
        max_ifg = max(ifgs)
        std_dev_ifg = statistics.stdev(ifgs)
        mean_ifg = statistics.mean(ifgs)
        counter_dict = {}
        for ifg in ifgs:
            counter_dict[ifg] = counter_dict.get(ifg, 0) + 1
        print(f"IFG stats min: {min_ifg:.2f} max: {max_ifg:.2f} mean: {mean_ifg:.2f} std_dev: {std_dev_ifg:.2f}")
        print(f"IFG instances: {counter_dict}")

    if counted_lp != expected_count_lp:
        errors += f"Did not get: {expected_count_lp} LP packets, got: {counted_lp} (dropped: {expected_count_lp-counted_lp})"

    if verbose:
        print(f"Counted {counted_lp} LP packets and {counted_hp} HP packets over {last_valid_packet_time/1e9:.2f}s")

    return errors if errors != "" else None



@pytest.mark.parametrize('send_method', ['socket', 'debugger'])
                                        # Format is LP packet size, HP packet size, Qav bandwidth bps
                                        # Restricting payload length to 1000 since the host cannot keep up with receiving small packets. Packet drops noticed for anything below 500 bytes.
@pytest.mark.parametrize('tx_config', [ [1000, 0, 0],
                                        [1000, 345, 1000000],
                                        [1514, 1514, 5000000],
                                        [1000, 1000, 25000000]]
                                        , ids=["LP_only", "LP_1Mbps_HP_small", "LP_max_len_2Mbps_HP_max", "LP_25Mbps_HP"]) 
def test_hw_mii_tx_only(request, send_method, tx_config):
    print()
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    if send_method == "socket":
        eth_intf = request.config.getoption("--eth-intf", default=None)
        assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"
        host_mac_address_str = get_mac_address(eth_intf)
        assert host_mac_address_str, f"get_mac_address() couldn't find mac address for interface {eth_intf}"
        print(f"host_mac_address = {host_mac_address_str}")
        host_mac_address = int(host_mac_address_str.replace(":", ""), 16)
    
    elif send_method == "debugger":
        dbg = hw_eth_debugger()
        host_mac_address_str = "d0:d1:d2:d3:d4:d5" # debugger doesn't care about this but DUT does and we can filter using this to get only DUT packets

    test_duration_s = request.config.getoption("--test-duration")
    if not test_duration_s:
        test_duration_s = 10
    test_duration_s = float(test_duration_s)

    # HP packet configuration
    hp_packet_len = tx_config[1]
    hp_packet_bandwidth_bps = tx_config[2]

    # LP packet configuration
    expected_packet_len_lp = tx_config[0]
    bits_per_packet = 8 * (expected_packet_len_lp + packet_overhead)
    total_bits = line_speed * test_duration_s
    total_bits *= (line_speed - hp_packet_bandwidth_bps) / line_speed # Subtract expected HP bandwidth
    expected_packet_count = int(total_bits / bits_per_packet)

    print(f"Setting DUT to send {expected_packet_count} LP packets of size {expected_packet_len_lp}")
    print(f"Setting DUT to send {hp_packet_bandwidth_bps} bps HP packets of size {hp_packet_len}")

    test_type = "seq_id"
    verbose = False
    seed = 0
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address_str_lp = "00:01:02:03:04:05"
    dut_mac_address_str_hp = "f0:f1:f2:f3:f4:f5"
    dut_mac_address_lp = int(dut_mac_address_str_lp.replace(":", ""), 16)
    dut_mac_address_hp = int(dut_mac_address_str_hp.replace(":", ""), 16)
    print(f"dut_mac_address_lp = 0x{dut_mac_address_lp:012x}")
    print(f"dut_mac_address_hp = 0x{dut_mac_address_hp:012x}")

    capture_file = "packets.bin"

    xe_name = pkg_dir / "hw_test_mii_tx" / "bin" / "hw_test_mii_tx_only.xe"
    with XcoreAppControl(adapter_id, xe_name, attach="xscope_app", verbose=verbose) as xcoreapp:
        print("Wait for DUT to be ready")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()

        # config contents of Tx packets
        lp_client_id = 0
        hp_client_id = 1
        xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(lp_client_id, dut_mac_address_str_lp)
        xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(hp_client_id, dut_mac_address_str_hp)
        xcoreapp.xscope_host.xscope_controller_cmd_set_host_macaddr(host_mac_address_str)

        if send_method == "socket":
            print("Starting socket sniffer")
            assert platform.system() in ["Linux"], f"Receiving using sockets only supported on Linux"
            socket_host = SocketHost(eth_intf, host_mac_address_str, f"{dut_mac_address_str_lp} {dut_mac_address_str_hp}", verbose=verbose)
            socket_host.recv_asynch_start(capture_file)

            # now signal to DUT that we are ready to receive and say what we want from it
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(hp_client_id, hp_packet_bandwidth_bps, hp_packet_len)
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(lp_client_id, expected_packet_count, expected_packet_len_lp)

            print(f"DUT sending packets for {test_duration_s}s..")

            host_received_packets = socket_host.recv_asynch_wait_complete()

            packet_summary = load_packet_file(capture_file)
            errors = parse_packet_summary(  packet_summary,
                                            expected_packet_count,
                                            expected_packet_len_lp,
                                            dut_mac_address_lp,
                                            expected_packet_len_hp = hp_packet_len,
                                            dut_mac_address_hp = dut_mac_address_hp,
                                            expected_bandwidth_hp = hp_packet_bandwidth_bps,
                                            verbose = True)


        elif send_method == "debugger":
            if dbg.wait_for_links_up():
                print("Links up")
            dbg.capture_start()

            # now signal to DUT that we are ready to receive and say what we want from it
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(hp_client_id, hp_packet_bandwidth_bps, hp_packet_len)
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_tx_packets(lp_client_id, expected_packet_count, expected_packet_len_lp)

            print(f"DUT sending packets for {test_duration_s}s..")

            time.sleep(test_duration_s + 1)

            packets = dbg.capture_stop()
            # we need to filter because debugger captures both ports
            filtered_packets = [pkt for pkt in packets if Ether in pkt and pkt[Ether].dst == host_mac_address_str]

            packet_summary = rdpcap_to_packet_summary(filtered_packets)
            errors = parse_packet_summary(  packet_summary,
                                            expected_packet_count,
                                            expected_packet_len_lp,
                                            dut_mac_address_lp,
                                            expected_packet_len_hp = hp_packet_len,
                                            dut_mac_address_hp = dut_mac_address_hp,
                                            expected_bandwidth_hp = hp_packet_bandwidth_bps,
                                            verbose = True,
                                            check_ifg = True)

        else:
            assert 0, f"Send method {send_method} not yet supported"

        print("Retrive status and shutdown DUT")

        stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()

    if errors:
        assert False, f"Various errors reported!!\n{errors}\n\nDUT stdout = {stdout}"
    else:
        print("TEST PASS")

# For local testing only
if __name__ == "__main__":
    packet_summary = load_packet_file("packets.bin")
    num_lp = 231701
    print(parse_packet_summary(packet_summary, 231701, 1000, 0x0102030405))
    print(parse_packet_summary(packet_summary, 231701, 1000, 0x0102030405, expected_packet_len_hp = 200, dut_mac_address_hp = 0xf0f1f2f3f4f5, expected_bandwidth_hp = None))
    print(parse_packet_summary(packet_summary, 231701, 1000, 0x0102030405, expected_packet_len_hp = 200, dut_mac_address_hp = 0xf0f1f2f3f4f5, expected_bandwidth_hp = 100000))
