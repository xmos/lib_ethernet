#!/usr/bin/env python
import xmostest
import os
import random
from mii_clock import Clock
from mii_phy import MiiTransmitter
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time


def do_test(impl, clk, phy):
    # The destination MAC address that has been set up in the filter on the device
    dut_mac_address = [0,1,2,3,4,5]
    
    packets = []
    error_packets = []

    # Part A - untagged frame

    # Valid maximum size untagged frame (1500 data + 18 header & CRC bytes)
    packets.append(MiiPacket(dst_mac_addr=dut_mac_address, create_data_args=['step', (1, 1500)],))

    # Oversized untagged frame - one byte too big for the 1522 bytes allowed per frame
    packet = MiiPacket(dst_mac_addr=dut_mac_address, create_data_args=['step', (2, 1505)],
                             inter_frame_gap=packet_processing_time(1500))
    packets.append(packet)
    error_packets.append(packet)

    # Oversized untagged frame - too big for the 1522 bytes allowed per frame
    packet = MiiPacket(dst_mac_addr=dut_mac_address, create_data_args=['step', (3, 1600)],
                             inter_frame_gap=packet_processing_time(1500))
    packets.append(packet)
    error_packets.append(packet)

    # Part B - VLAN/Prio tagged frame
    vlan_prio_tag = [0x81, 0x00, 0x00, 0x00]

    # Valid maximum size tagged frame (1500 data + 22 header & CRC bytes)
    packets.append(MiiPacket(dst_mac_addr=dut_mac_address, vlan_prio_tag=vlan_prio_tag,
                             create_data_args=['step', (10, 1500)],))

    # Oversized tagged frame - just one byte too big
    packet = MiiPacket(dst_mac_addr=dut_mac_address, vlan_prio_tag=vlan_prio_tag,
                             create_data_args=['step', (11, 1501)],
                             inter_frame_gap=packet_processing_time(1500))
    packets.append(packet)
    error_packets.append(packet)

    # Oversized tagged frame
    packet = MiiPacket(dst_mac_addr=dut_mac_address, vlan_prio_tag=vlan_prio_tag,
                             create_data_args=['step', (12, 1549)],
                             inter_frame_gap=packet_processing_time(1500))
    packets.append(packet)
    error_packets.append(packet)

    # Part C
    # TODO - oversized envelope frame

    # Part D
    # Don't support flow control - so don't run

    # Part E
    # Parts A - C with valid frames before/after the errror frame
    ifg = clk.get_min_ifg()
    for i,packet in enumerate(error_packets):
      # First valid frame (allowing time to process previous two valid frames)
      packets.append(MiiPacket(dst_mac_addr=dut_mac_address,
                               create_data_args=['step', (i%10, 46)],
                               inter_frame_gap=2*packet_processing_time(46)))

      # Error frame after minimum IFG
      packet.inter_frame_gap = ifg
      packets.append(packet)

      # Second valid frame with minimum IFG
      packets.append(MiiPacket(dst_mac_addr=dut_mac_address,
                               create_data_args=['step', (2 * ((i+1)%10), 46)],
                               inter_frame_gap=ifg))
    
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
