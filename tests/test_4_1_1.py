#!/usr/bin/env python
import xmostest
import os
import random
from mii_clock import Clock
from mii_phy import MiiTransmitter
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address


def do_test(impl, clk, phy):
    dut_mac_address = get_dut_mac_address()

    # Part A
    packets = [ MiiPacket(create_data_args=['step', (3, 46)], corrupt_crc=True) ]
#    controller.dumpStats()

    # Part B
    packets = packets + [
        MiiPacket(                                   create_data_args=['step', (4, 46)]),
        MiiPacket(inter_frame_gap=clk.get_min_ifg(), create_data_args=['step', (5, 46)], corrupt_crc=True),
        MiiPacket(inter_frame_gap=clk.get_min_ifg(), create_data_args=['step', (6, 46)])
      ]
 #   controller.dumpStats()

    # Set all the destination MAC addresses to get through the filtering
    for packet in packets:
        packet.dst_mac_addr = dut_mac_address

    do_rx_test(impl, clk, phy, packets, __file__)


def runtest():
    random.seed(1)

    # Test 100 MBit - MII
    clock_25 = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_25MHz)
    mii = MiiTransmitter('tile[0]:XS1_PORT_1A',
                         'tile[0]:XS1_PORT_4E',
                         'tile[0]:XS1_PORT_1K',
                         clock_25)

    do_test("standard", clock_25, mii)
    do_test("rt", clock_25, mii)

