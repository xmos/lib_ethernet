# Copyright 2014-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
from mii_clock import Clock
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, run_parametrised_test_rx
import pytest
from pathlib import Path
from helpers import generate_tests

def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed, rx_width=None, tx_width=None):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    packets = []

    # Part A - Send different length preambles and ensure the packets are still received
    # Check a selection of preamble lengths from 1 byte to 64 bytes (including SFD)
    test_lengths = [3, 4, 5, 61, 127]
    if tx_clk.get_rate() == Clock.CLK_125MHz:
        # The RGMII requires a longer preamble
        test_lengths = [5, 7, 9, 61, 127]

    for num_preamble_nibbles in test_lengths:
        packets.append(MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            num_preamble_nibbles=num_preamble_nibbles,
            create_data_args=['step', (rand.randint(1, 254), choose_small_frame_size(rand))],
            inter_frame_gap=packet_processing_time(tx_phy, 46, mac)
          ))

    do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed, override_dut_dir="test_rx", rx_width=rx_width, tx_width=tx_width)

test_params_file = Path(__file__).parent / "test_rx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_4_2_4(params, capfd):
    if params["phy"] == "rmii":
        pytest.skip("Failing for rmii. https://github.com/xmos/lib_ethernet/issues/72")
    random.seed(24)
    run_parametrised_test_rx(capfd, do_test, params)
