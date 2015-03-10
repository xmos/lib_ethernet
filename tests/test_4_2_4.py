#!/usr/bin/env python

import random
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, runall_rx
from mii_clock import Clock

def do_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed):
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

    do_rx_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed)

def runtest():
    random.seed(24)
    runall_rx(do_test)
