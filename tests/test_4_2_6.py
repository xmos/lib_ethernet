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

    packets = []

    ifg = clk.get_min_ifg()

    # Part A - Ensure that two packets separated by minimum IFG are received ok
    packets.append(MiiPacket(
        dst_mac_addr=dut_mac_address,
        create_data_args=['step', (rand.randint(1, 254), choose_small_frame_size(rand))]
      ))
    packets.append(MiiPacket(
        dst_mac_addr=dut_mac_address,
        create_data_args=['step', (rand.randint(1, 254), choose_small_frame_size(rand))],
        inter_frame_gap=ifg
      ))

    # Part B - Determine the minimum IFG that can be supported
    bit_time = ifg/96

    # Allow lots of time for the DUT to recover between test bursts
    recovery_time = 4*packet_processing_time(46)

    # Test shrinking the IFG by different amounts. Use the shrink as the step for debug purposes
    for gap_shrink in [10, 20, 30, 40, 50, 55, 60, 65]:
        new_ifg = ifg - gap_shrink * bit_time

        packets.append(MiiPacket(
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (gap_shrink, choose_small_frame_size(rand))],
            inter_frame_gap=recovery_time
          ))
        packets.append(MiiPacket(
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (gap_shrink, choose_small_frame_size(rand))],
            inter_frame_gap=new_ifg
          ))

    do_rx_test(impl, clk, phy, packets, __file__, seed)


def runtest():
    random.seed(6)

    # Test 100 MBit - MII
    clock_25 = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_25MHz)
    mii = MiiTransmitter('tile[0]:XS1_PORT_1A',
                         'tile[0]:XS1_PORT_4E',
                         'tile[0]:XS1_PORT_1K',
                         clock_25)

    do_test("standard", clock_25, mii, random.randint(0, sys.maxint))
    do_test("rt", clock_25, mii, random.randint(0, sys.maxint))
