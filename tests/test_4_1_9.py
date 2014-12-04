#!/usr/bin/env python
import xmostest
import os
import random
import copy
import sys
from mii_clock import Clock
from mii_phy import MiiTransmitter
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size


def do_test(impl, clk, phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    error_packets = []

    # Part A - Invalid preamble nibbles, but the frame should still be received
    preamble_nibbles = [0x5, 0x5, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x5]
    if clk.get_rate() == Clock.CLK_125MHz:
        preamble_nibbles = [0x5, 0x5, 0x5, 0x5, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x5]

    error_packets.append(MiiPacket(
        dst_mac_addr=dut_mac_address,
        preamble_nibbles=preamble_nibbles,
        create_data_args=['step', (rand.randint(1, 254), choose_small_frame_size(rand))]
      ))

    # Part B - Invalid preamble nibbles, but the packet should still be received
    preamble_nibbles = [0x5, 0x5, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0x5]
    if clk.get_rate() == Clock.CLK_125MHz:
        preamble_nibbles = [0x5, 0x5, 0x5, 0x5, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0xf, 0x5]

    error_packets.append(MiiPacket(
        dst_mac_addr=dut_mac_address,
        preamble_nibbles=preamble_nibbles,
        create_data_args=['step', (rand.randint(1, 254), choose_small_frame_size(rand))],
        inter_frame_gap=packet_processing_time(46)
      ))

    # Part C - Invalid preamble nibbles, but the packet should still be received
    preamble_nibbles = [0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x8, 0x5, 0xf, 0x5]

    error_packets.append(MiiPacket(
        dst_mac_addr=dut_mac_address,
        preamble_nibbles=preamble_nibbles,
        create_data_args=['step', (rand.randint(1, 254), choose_small_frame_size(rand))],
        inter_frame_gap=packet_processing_time(46)
      ))

    # Part D - Parts A, B and C with valid frames before/after the errror frame
    packets = []
    for packet in error_packets:
        packets.append(packet)

    ifg = clk.get_min_ifg()
    for i,packet in enumerate(error_packets):
      # First valid frame (allowing time to process previous two valid frames)
      packets.append(MiiPacket(
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (i%10, choose_small_frame_size(rand))],
          inter_frame_gap=3*packet_processing_time(46)
        ))

      # Take a copy to ensure that the original is not modified
      packet_copy = copy.deepcopy(packet)

      # Error frame after minimum IFG
      packet_copy.inter_frame_gap = ifg
      packets.append(packet_copy)

      # Second valid frame with minimum IFG
      packets.append(MiiPacket(
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (2 * ((i+1)%10), choose_small_frame_size(rand))],
          inter_frame_gap=ifg
        ))

    do_rx_test(impl, clk, phy, packets, __file__, seed)


def runtest():
    random.seed(8)

    # Test 100 MBit - MII
    clock_25 = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_25MHz)
    mii = MiiTransmitter('tile[0]:XS1_PORT_1A',
                         'tile[0]:XS1_PORT_4E',
                         'tile[0]:XS1_PORT_1K',
                         clock_25)

    do_test("standard", clock_25, mii, random.randint(0, sys.maxint))
    do_test("rt", clock_25, mii, random.randint(0, sys.maxint))
