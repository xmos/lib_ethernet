#!/usr/bin/env python
import xmostest
import os
import random
import copy
from mii_clock import Clock
from mii_phy import MiiTransmitter
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address


def do_test(impl, clk, phy):
    dut_mac_address = get_dut_mac_address()

    error_packets = []

    # Part A - Valid packet with an extra nibble (should be accepted)
    error_packets.append(MiiPacket(
        dst_mac_addr=dut_mac_address,
        extra_nibble=True,
        create_data_args=['step', (22, 46)]
      ))

    # Part B - Invalid packet with an extra nibble (should be reported as alignmentError)
    error_packets.append(MiiPacket(
        dst_mac_addr=dut_mac_address,
        extra_nibble=True, corrupt_crc=True,
        create_data_args=['step', (23, 46)]
      ))

    # Part C - Parts A and B with valid frames before/after the errror frame
    packets = []
    for packet in error_packets:
        packets.append(packet)

    ifg = clk.get_min_ifg()
    for i,packet in enumerate(error_packets):
      # First valid frame (allowing time to process previous two valid frames)
      packets.append(MiiPacket(
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (i%10, 46)],
          inter_frame_gap=2*packet_processing_time(46)
        ))

      # Take a copy to ensure that the original is not modified
      packet_copy = copy.deepcopy(packet)

      # Error frame after minimum IFG
      packet_copy.inter_frame_gap = ifg
      packets.append(packet_copy)

      # Second valid frame with minimum IFG
      packets.append(MiiPacket(
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (2 * ((i+1)%10), 46)],
          inter_frame_gap=ifg
        ))

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
