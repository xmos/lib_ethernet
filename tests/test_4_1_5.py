# Copyright 2014-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

"""
Host sends packets where the len/type field indicates a length less than the actual payload length.
The DUT is expected to receive these frames but report a length which is coded in the len/type field.
"""

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

    excess_pad_packets = []

    # Part A - excessive pad
    processing_time = 0
    # These packets should not be dropped (though the standard is ambiguous). The length, however
    # should be reported as the length specified in the len/type field.
    for (num_data_bytes, len_type, step) in [(47, 46, 20), (1504, 46, 21), (1504, 1503, 22)]:
        excess_pad_packets.append(MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            ether_len_type=[(len_type >> 8) & 0xff, len_type & 0xff],
            create_data_args=['step', (step, num_data_bytes)],
            inter_frame_gap=processing_time
          ))

        # Update packet processing time so that next packet leaves enough time before starting
        processing_time = packet_processing_time(tx_phy, num_data_bytes, mac)

    # Part B - Part A with valid frames before/after the errror frame
    packets = []
    for packet in excess_pad_packets:
        packets.append(packet)

    ifg = tx_clk.get_min_ifg()
    for i,packet in enumerate(excess_pad_packets):
      # First valid frame (allowing time to process previous two valid frames)
      packets.append(MiiPacket(rand,
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (i%10, choose_small_frame_size(rand))],
          inter_frame_gap=2*packet_processing_time(tx_phy, 46, mac) + packet_processing_time(tx_phy, 1518, mac)
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
def test_4_1_5(params, capfd):
    random.seed(15)
    run_parametrised_test_rx(capfd, do_test, params)
