#!/usr/bin/env python
import xmostest
import os
import random
import sys
from mii_clock import Clock
from mii_phy import MiiTransmitter
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address
from helpers import choose_small_frame_size


def do_test(impl, clk, phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    packets = []

    # Part A
    packets.append(MiiPacket(
        create_data_args=['step', (3, choose_small_frame_size(rand))],
        corrupt_crc=True,
        dropped=True
      ))

    # Part B
    packets.append(MiiPacket(
        create_data_args=['step', (4, choose_small_frame_size(rand))]
      ))

    packets.append(MiiPacket(
        inter_frame_gap=clk.get_min_ifg(),
        create_data_args=['step', (5, choose_small_frame_size(rand))],
        corrupt_crc=True,
        dropped=True
      ))

    packets.append(MiiPacket(
        inter_frame_gap=clk.get_min_ifg(),
        create_data_args=['step', (6, choose_small_frame_size(rand))]
      ))

    # Set all the destination MAC addresses to get through the filtering
    for packet in packets:
        packet.dst_mac_addr = dut_mac_address

    do_rx_test(impl, clk, phy, packets, __file__, seed)


def runtest():
    random.seed(1)

    # Test 100 MBit - MII
    clock_25 = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_25MHz)
    mii = MiiTransmitter('tile[0]:XS1_PORT_1A',
                         'tile[0]:XS1_PORT_4E',
                         'tile[0]:XS1_PORT_1K',
                         clock_25)

    do_test("standard", clock_25, mii, random.randint(0, sys.maxint))
    do_test("rt", clock_25, mii, random.randint(0, sys.maxint))

