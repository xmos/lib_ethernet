# Copyright 2014-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
import copy
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, run_parametrised_test_rx

import pytest
from pathlib import Path
from helpers import generate_tests

def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed, rx_width=None, tx_width=None, hw_debugger_test=None):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    packets = []
    error_packets = []

    # Part A - untagged frame

    # Valid maximum size untagged frame (1500 data + 18 header & CRC bytes)
    packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address, create_data_args=['step', (1, 1500)]
      ))

    # Oversized untagged frame - one byte too big for the 1522 bytes allowed per frame
    packet = MiiPacket(rand,
        dst_mac_addr=dut_mac_address, create_data_args=['step', (2, 1505)],
        inter_frame_gap=packet_processing_time(tx_phy, 1500, mac),
        dropped=True
      )
    packets.append(packet)
    error_packets.append(packet)

    # Oversized untagged frame - too big for the 1522 bytes allowed per frame
    packet = MiiPacket(rand,
        dst_mac_addr=dut_mac_address, create_data_args=['step', (3, 1600)],
        inter_frame_gap=packet_processing_time(tx_phy, 1500, mac),
        dropped=True
      )
    packets.append(packet)
    error_packets.append(packet)

    # Part B - VLAN/Prio tagged frame
    vlan_prio_tag = [0x81, 0x00, 0x00, 0x00]

    # Valid maximum size tagged frame (1500 data + 22 header & CRC bytes)
    packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address, vlan_prio_tag=vlan_prio_tag,
        create_data_args=['step', (10, 1500)]
      ))

    # Oversized tagged frame - just one byte too big
    packet = MiiPacket(rand,
        dst_mac_addr=dut_mac_address, vlan_prio_tag=vlan_prio_tag,
        create_data_args=['step', (11, 1501)],
        inter_frame_gap=packet_processing_time(tx_phy, 1500, mac),
        dropped=True
      )
    packets.append(packet)
    error_packets.append(packet)

    # Oversized tagged frame
    packet = MiiPacket(rand,
        dst_mac_addr=dut_mac_address, vlan_prio_tag=vlan_prio_tag,
        create_data_args=['step', (12, 1549)],
        inter_frame_gap=packet_processing_time(tx_phy, 1500, mac),
        dropped=True
      )
    packets.append(packet)
    error_packets.append(packet)

    # Part C
    # TODO - oversized envelope frame

    # Part D
    # Don't support flow control - so don't run

    # Part E
    # Parts A - C with valid frames before/after the errror frame
    ifg = tx_clk.get_min_ifg()
    for i,packet in enumerate(error_packets):
      # First valid frame (allowing time to process previous two valid frames)
      packets.append(MiiPacket(rand,
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (i%10, choose_small_frame_size(rand))],
          inter_frame_gap=2*packet_processing_time(tx_phy, 46, mac)
        ))

      # Take a copy to ensure that the original is not modified
      packet_copy = copy.deepcopy(packet)

      # Error frame after minimum IFG
      packet_copy.set_ifg(ifg)
      packets.append(packet_copy)

      # Second valid frame with minimum IFG
      packets.append(MiiPacket(rand,
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (2 * ((i+1)%10), choose_small_frame_size(rand))],
          inter_frame_gap=ifg
        ))

    if hw_debugger_test is not None:
        test_fn = hw_debugger_test[0]
        request = hw_debugger_test[1]
        testname = hw_debugger_test[2]
        test_fn(request, testname, mac, arch, packets)
    else:
        do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed, override_dut_dir="test_rx", rx_width=rx_width, tx_width=tx_width)

test_params_file = Path(__file__).parent / "test_rx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_4_1_3(params, capfd):
    random.seed(13)
    run_parametrised_test_rx(capfd, do_test, params, exclude_standard=True)

