#!/usr/bin/env python

import random
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, runall_rx

def do_test(impl, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    packets = []

    # Part A - Send different length preambles and ensure the packets are still received
    # Check a selection of preamble lengths from 1 byte to 64 bytes (including SFD)
    for num_preamble_nibbles in [2, 3, 4, 61, 127]:
        packets.append(MiiPacket(
            dst_mac_addr=dut_mac_address,
            num_preamble_nibbles=num_preamble_nibbles,
            create_data_args=['step', (rand.randint(1, 254), choose_small_frame_size(rand))],
            inter_frame_gap=packet_processing_time(46)
          ))

    do_rx_test(impl, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed)

def runtest():
    random.seed(24)
    runall_rx(do_test)
