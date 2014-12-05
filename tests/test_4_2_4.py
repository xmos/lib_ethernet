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

    # Part A - Send different length preambles and ensure the packets are still received
    # Check a selection of preamble lengths from 1 byte to 64 bytes (including SFD)
    for num_preamble_nibbles in [2, 3, 4, 61, 127]:
        packets.append(MiiPacket(
            dst_mac_addr=dut_mac_address,
            num_preamble_nibbles=num_preamble_nibbles,
            create_data_args=['step', (rand.randint(1, 254), choose_small_frame_size(rand))],
            inter_frame_gap=packet_processing_time(46)
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
