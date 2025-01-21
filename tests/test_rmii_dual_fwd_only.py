# Copyright 2024-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

"""
DUT receives packets on both ports.
None of the packets received by the DUT are meant for the client running on the DUT, so
they get forwarded on the other port.
So, the sim phy port 0, receives packets that were sent to dut mac port 1 and vice versa
"""

import random
import Pyxsim as px
from pathlib import Path
import pytest
import sys, os
import numpy as np

from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, run_parametrised_test_rx, check_received_packet
from helpers import generate_tests, create_if_needed, create_expect, get_sim_args
from helpers import get_rmii_clk, get_rmii_tx_phy_dual, get_rmii_rx_phy_dual
from rmii_phy import RMiiTransmitter, RMiiReceiver
from helpers import do_rx_test_dual


def rmii_dual_fwd_test(capfd, params, seed):
    rand = random.Random()
    rand.seed(seed)
    verbose = False

    # Instantiate clk and phys
    clk = get_rmii_clk(Clock.CLK_50MHz)
    tx_rmii_phy, tx_rmii_phy_2 = get_rmii_tx_phy_dual(
                                    [params['rx_width'], params['rx_width']],
                                    clk,
                                    verbose=verbose
                                    )

    rx_rmii_phy, rx_rmii_phy_2 = get_rmii_rx_phy_dual(
                                    [params['tx_width'], params['tx_width']],
                                    clk,
                                    packet_fn=check_received_packet,
                                    verbose=verbose
                                    )


    mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, rx_width, tx_width = params["mac"], params["arch"], None, [rx_rmii_phy, rx_rmii_phy_2], clk, [tx_rmii_phy, tx_rmii_phy_2], params['rx_width'],params['tx_width']



    dut_mac_address = get_dut_mac_address() # Mac address for which the client running on the DUT will register to receive packets

    # non dut mac address, packets destined for which get forwarded on the other port
    not_dut_mac_address_0 = [] # Mac address which is different from the one for which the client running on the DUT has registered to receive packets
    not_dut_mac_address_1 = [] # Mac address which is different from the one for which the client running on the DUT has registered to receive packets
    for i in range(6):
        not_dut_mac_address_0.append(dut_mac_address[i]+1)
        not_dut_mac_address_1.append(dut_mac_address[i]+2)

    num_test_packets = 50

    packets_mac_0 = []  # Packets arriving on mac rx port 0. These get forwarded to tx port 1
    packets_mac_1 = []  # Packets arriving on mac rx port 1. These get forwarded to tx port 0


    # Send frames which excercise all of the tail length vals (0, 1, 2, 3 bytes)
    packet_start_len = 100
    ifg = tx_clk.get_min_ifg()

    for i in range(num_test_packets):
        packets_mac_0.append(MiiPacket(rand,
            dst_mac_addr=not_dut_mac_address_0,
            create_data_args=['step', (i, packet_start_len + i)],
            inter_frame_gap=ifg
        ))
        packets_mac_1.append(MiiPacket(rand,
            dst_mac_addr=not_dut_mac_address_1,
            create_data_args=['step', (2*i, packet_start_len + 2*i)],
            inter_frame_gap=ifg
        ))

    tx_phy[0].set_packets(packets_mac_0)
    tx_phy[1].set_packets(packets_mac_1)

    rx_phy[0].set_expected_packets(packets_mac_1)
    rx_phy[1].set_expected_packets(packets_mac_0)

    do_rx_test_dual(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, [packets_mac_0, packets_mac_1], __file__, seed, rx_width=rx_width, tx_width=tx_width, override_dut_dir="test_rmii_dual_basic")



test_params_file = Path(__file__).parent / "test_rmii_dual_basic/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_rmii_dual_fwd_only(capfd, seed, params):
    with capfd.disabled():
        print(params)

    if seed == None:
        seed = random.randint(0, sys.maxsize)

    rmii_dual_fwd_test(capfd, params, seed)
