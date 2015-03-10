#!/usr/bin/env python

import random
import copy
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, runall_rx

def do_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    packets = []
    error_packets = []

    # Part A - untagged frame

    # Valid maximum size untagged frame (1500 data + 18 header & CRC bytes)
    packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address, create_data_args=['step', (1, 1500)]
      ))

    # Oversized untagged frame - one byte too big for the 1522 bytes allowed per frame
    packet = MiiPacket(rand,
        dst_mac_addr=dut_mac_address, create_data_args=['step', (2, 1505)],
        inter_frame_gap=packet_processing_time(tx_phy, 1500, mac),
        dropped=True
      )
    packets.append(packet)
    error_packets.append(packet)

    # Oversized untagged frame - too big for the 1522 bytes allowed per frame
    packet = MiiPacket(rand,
        dst_mac_addr=dut_mac_address, create_data_args=['step', (3, 1600)],
        inter_frame_gap=packet_processing_time(tx_phy, 1500, mac),
        dropped=True
      )
    packets.append(packet)
    error_packets.append(packet)

    # Part B - VLAN/Prio tagged frame
    vlan_prio_tag = [0x81, 0x00, 0x00, 0x00]

    # Valid maximum size tagged frame (1500 data + 22 header & CRC bytes)
    packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address, vlan_prio_tag=vlan_prio_tag,
        create_data_args=['step', (10, 1500)]
      ))

    # Oversized tagged frame - just one byte too big
    packet = MiiPacket(rand,
        dst_mac_addr=dut_mac_address, vlan_prio_tag=vlan_prio_tag,
        create_data_args=['step', (11, 1501)],
        inter_frame_gap=packet_processing_time(tx_phy, 1500, mac),
        dropped=True
      )
    packets.append(packet)
    error_packets.append(packet)

    # Oversized tagged frame
    packet = MiiPacket(rand,
        dst_mac_addr=dut_mac_address, vlan_prio_tag=vlan_prio_tag,
        create_data_args=['step', (12, 1549)],
        inter_frame_gap=packet_processing_time(tx_phy, 1500, mac),
        dropped=True
      )
    packets.append(packet)
    error_packets.append(packet)

    # Part C
    # TODO - oversized envelope frame

    # Part D
    # Don't support flow control - so don't run

    # Part E
    # Parts A - C with valid frames before/after the errror frame
    ifg = tx_clk.get_min_ifg()
    for i,packet in enumerate(error_packets):
      # First valid frame (allowing time to process previous two valid frames)
      packets.append(MiiPacket(rand,
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (i%10, choose_small_frame_size(rand))],
          inter_frame_gap=2*packet_processing_time(tx_phy, 46, mac)
        ))

      # Take a copy to ensure that the original is not modified
      packet_copy = copy.deepcopy(packet)

      # Error frame after minimum IFG
      packet_copy.set_ifg(ifg)
      packets.append(packet_copy)

      # Second valid frame with minimum IFG
      packets.append(MiiPacket(rand,
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (2 * ((i+1)%10), choose_small_frame_size(rand))],
          inter_frame_gap=ifg
        ))

    do_rx_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed)

def runtest():
    random.seed(13)
    runall_rx(do_test)
