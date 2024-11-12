# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, run_parametrised_test_rx
import pytest
from pathlib import Path
import json

with open(Path(__file__).parent / "test_rx/test_params.json") as f:
    params = json.load(f)


def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    packets = []

    # Part A
    packets.append(MiiPacket(rand,
        create_data_args=['step', (3, choose_small_frame_size(rand))],
        corrupt_crc=True,
        dropped=True
      ))

    # Part B
    packets.append(MiiPacket(rand,
        create_data_args=['step', (4, choose_small_frame_size(rand))]
      ))

    packets.append(MiiPacket(rand,
        inter_frame_gap=tx_clk.get_min_ifg(),
        create_data_args=['step', (5, choose_small_frame_size(rand))],
        corrupt_crc=True,
        dropped=True
      ))

    packets.append(MiiPacket(rand,
        inter_frame_gap=tx_clk.get_min_ifg(),
        create_data_args=['step', (6, choose_small_frame_size(rand))]
      ))

    # Set all the destination MAC addresses to get through the filtering
    for packet in packets:
        packet.dst_mac_addr = dut_mac_address

    do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed, override_dut_dir="test_rx")

@pytest.mark.parametrize("params", params["PROFILES"], ids=["-".join(list(profile.values())) for profile in params["PROFILES"]])
def test_4_1_1(params, capfd):
    random.seed(11)
    run_parametrised_test_rx(capfd, do_test, params)
