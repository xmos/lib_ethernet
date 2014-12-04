#!/usr/bin/env python
import xmostest
import os
import random
import sys
from mii_clock import Clock
from mii_phy import MiiTransmitter
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time
from helpers import choose_small_frame_size


def do_test(impl, clk, phy, seed):
    rand = random.Random()
    rand.seed(seed)

    # The destination MAC address that has been set up in the filter on the device
    dut_mac_address = [0,1,2,3,4,5]

    # The inter-frame gap is to give the DUT time to print its output
    packets = [
        MiiPacket(
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (1, 72)]
          ),

        MiiPacket(
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (5, 52)],
            inter_frame_gap=packet_processing_time(72)
          ),

        MiiPacket(
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (7, 1500)],
            inter_frame_gap=packet_processing_time(52)
          )
      ]

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

#    # Test 100 MBit - RGMII
#    clock_25 = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_25MHz)
#    rgmii = RgmiiTransmitter('tile[0]:XS1_PORT_1A',
#                         'tile[0]:XS1_PORT_4E',
#                         'tile[0]:XS1_PORT_1K',
#                         clock_25)
#
#    do_test("rt", clock_25, rgmii)
#
#    # Test Gigabit - RGMII
#    clock_125 = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_125MHz)
#    rgmii.clock = clock_125
#
#    do_test("rt", clock_125, rgmii)


