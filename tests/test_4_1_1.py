#!/usr/bin/env python

import random
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, runall_rx

def do_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed):
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

    do_rx_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed)

def runtest():
    random.seed(11)
    runall_rx(do_test)
