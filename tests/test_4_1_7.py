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

    error_packets = []

    # Part A - Invalid SFD nibble: use preamble nibble (0x5)
    error_packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address,
        sfd_nibble=0x5,
        create_data_args=['step', (19, choose_small_frame_size(rand))],
        dropped=True
      ))

    # Part B - Invalid SFD: replace last byte of preamble with 0x9 instead of 0x5
    error_packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address,
        preamble_nibbles=[0x5 for x in range(14)] + [0x9],
        create_data_args=['step', (20, choose_small_frame_size(rand))],
        dropped=True
      ))

    # Part C - Parts A and B with valid frames before/after the errror frame
    packets = []
    for packet in error_packets:
        packets.append(packet)

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
    random.seed(17)
    runall_rx(do_test)
