# Copyright 2014-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
import copy
import pytest
from pathlib import Path
import sys

from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, run_parametrised_test_rx
from helpers import generate_tests

def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    error_packets = []

    # Test that packets where the RXER line goes high are dropped even
    # if the rest of the packet is valid

    # Error on the first nibble of the preamble
    num_data_bytes = choose_small_frame_size(rand)
    error_packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address,
        num_data_bytes=num_data_bytes,
        error_nibbles=[0],
        dropped=True
      ))

    # Error somewhere in the middle of the packet
    num_data_bytes = choose_small_frame_size(rand)
    error_packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address,
        num_data_bytes=num_data_bytes,
        dropped=True
      ))
    packet = error_packets[-1]
    error_nibble = rand.randint(packet.num_preamble_nibbles + 1, len(packet.get_nibbles()))
    packet.error_nibbles = [error_nibble]

    # Due to BUG 16233 the RGMII code won't always detect an error in the last two bytes
    num_data_bytes = choose_small_frame_size(rand)
    error_packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address,
        num_data_bytes=num_data_bytes,
        dropped=True
      ))
    packet = error_packets[-1]
    packet.error_nibbles = [len(packet.get_nibbles()) - 5]

    # Now run all packets with valid frames before/after the errror frame to ensure the
    # errors don't interfere with valid frames
    packets = []
    for packet in error_packets:
        packets.append(packet)

    ifg = tx_clk.get_min_ifg()
    for i,packet in enumerate(error_packets):
      # First valid frame (allowing time to process previous two valid frames)
      packets.append(MiiPacket(rand,
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (i%10, choose_small_frame_size(rand))],
          inter_frame_gap=3*packet_processing_time(tx_phy, 46, mac)
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

    do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed, override_dut_dir="test_rx")

    random.seed(1)

test_params_file = Path(__file__).parent / "test_rx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_rx_err(capfd, seed, params):
    if params["phy"] == "rmii":
      pytest.skip("RX_ER not supported on RMII")

    if seed == None:
        seed = random.randint(0, sys.maxsize)


    # Issue #30 - the standard MII ignores the RX_ER signal
    run_parametrised_test_rx(capfd, do_test, params, exclude_standard=True, seed=seed)

