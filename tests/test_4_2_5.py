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

    # Part A - Test the sending of all valid size untagged frames
    processing_time = packet_processing_time(46)
    for num_data_bytes in [46, choose_small_frame_size(rand), 1500]:
        packets.append(MiiPacket(
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (rand.randint(1, 254), num_data_bytes)],
            inter_frame_gap=processing_time
          ))
        processing_time = packet_processing_time(num_data_bytes)

    # Part B - Test the sending of sub 46 bytes of data in the length field but valid minimum packet sizes
    # The packet sizes longer than this are covered by Part A
    for len_type in [1, 2, 3, 4, 15, 45]:
        packets.append(MiiPacket(
            dst_mac_addr=dut_mac_address,
            ether_len_type=[(len_type >> 8) & 0xff, len_type & 0xff],
            create_data_args=['step', (rand.randint(1, 254), 46)],
            inter_frame_gap=packet_processing_time(46)
          ))

    # Part C - Test the sending of all valid size tagged frames
    processing_time = packet_processing_time(46)
    for num_data_bytes in [42, choose_small_frame_size(rand), 1500]:
        packets.append(MiiPacket(
            dst_mac_addr=dut_mac_address,
            vlan_prio_tag=[0x81, 0x00, 0x00, 0x00],
            create_data_args=['step', (rand.randint(1, 254), num_data_bytes)],
            inter_frame_gap=processing_time
          ))
        processing_time = packet_processing_time(num_data_bytes)

    # Part D
    # Not supporting 802.3-2012, so no envelope frames

    # Part E
    # Not doing half duplex 1000Mb/s, so don't test this
        
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
