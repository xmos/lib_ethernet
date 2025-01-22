# Copyright 2024-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
import Pyxsim as px
from pathlib import Path
import pytest
import sys, os

from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, run_parametrised_test_rx, check_received_packet
from helpers import generate_tests
from helpers import get_rmii_clk, get_rmii_tx_phy_dual, get_rmii_rx_phy_dual
from rmii_phy import RMiiTransmitter, RMiiReceiver
from helpers import do_rx_test_dual


test_params_file = Path(__file__).parent / "test_rmii_dual_basic/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_rmii_dual_basic(capfd, seed, params):
    with capfd.disabled():
        print(params)

    if seed == None:
        seed = random.randint(0, sys.maxsize)

    rand = random.Random()
    rand.seed(seed)
    verbose = False

    # Instantiate clk and phys
    clk = get_rmii_clk(Clock.CLK_50MHz)
    tx_rmii_phy, tx_rmii_phy_2 = get_rmii_tx_phy_dual(
                                    [params['rx_width'], params['rx_width']],
                                    clk,
                                    verbose=verbose,
                                    expect_loopback=True
                                    )

    rx_rmii_phy, rx_rmii_phy_2 = get_rmii_rx_phy_dual(
                                    [params['tx_width'], params['tx_width']],
                                    clk,
                                    packet_fn=check_received_packet,
                                    verbose=verbose
                                    )

    mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, rx_width, tx_width = params["mac"], params["arch"], None, [rx_rmii_phy, rx_rmii_phy_2], clk, [tx_rmii_phy, tx_rmii_phy_2], params['rx_width'],params['tx_width']

    dut_mac_address = get_dut_mac_address()
    not_dut_mac_address = []
    for i in range(6):
        not_dut_mac_address.append(dut_mac_address[i]+1)

    num_test_packets = 30
    packets = []
    loopback_packets = []
    forwarded_packets = []

    # Send frames which excercise all of the tail length vals (0, 1, 2, 3 bytes)
    packet_start_len = 100
    # Packets that get looped back on the same port
    for i in range(num_test_packets):
        loopback_packets.append(MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (i, packet_start_len + i)],
            inter_frame_gap=201*clk.get_bit_time()
        ))
    # packets that get forwarded to the other port
    for i in range(num_test_packets):
        forwarded_packets.append(MiiPacket(rand,
            dst_mac_addr=not_dut_mac_address,
            create_data_args=['step', (i, packet_start_len + i)],
            inter_frame_gap=201*clk.get_bit_time()
        ))

    # interleave loopback and forwarded packets
    for i in range(num_test_packets):
        packets.append(loopback_packets[i])
        packets.append(forwarded_packets[i])

    tx_phy[1].set_packets(packets) # Send all packets to mac port 1
    rx_phy[1].set_expected_packets(loopback_packets)  # Looped back packets show up on port 1 of the sim phy
    rx_phy[0].set_expected_packets(forwarded_packets) # Forwarded packets show up on port 0 of the sim phy


    do_rx_test_dual(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, [forwarded_packets, loopback_packets], __file__, seed, rx_width=rx_width, tx_width=tx_width)


