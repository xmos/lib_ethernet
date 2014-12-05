#!/usr/bin/env python

import random
import copy
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, runall_rx

def do_test(impl, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    excess_pad_packets = []

    # Part A - excessive pad
    processing_time = 0
    # These packets should not be dropped (though the standard is ambiguous). The length, however
    # should be reported as the length specified in the len/type field.
    for (num_data_bytes, len_type, step) in [(47, 46, 20), (1504, 46, 21), (1504, 1503, 22)]:
        excess_pad_packets.append(MiiPacket(
            dst_mac_addr=dut_mac_address,
            ether_len_type=[(len_type >> 8) & 0xff, len_type & 0xff],
            create_data_args=['step', (step, num_data_bytes)],
            inter_frame_gap=processing_time
          ))

        # Update packet processing time so that next packet leaves enough time before starting
        processing_time = packet_processing_time(num_data_bytes)

    # Part B - Part A with valid frames before/after the errror frame
    packets = []
    for packet in excess_pad_packets:
        packets.append(packet)

    ifg = tx_clk.get_min_ifg()
    for i,packet in enumerate(excess_pad_packets):
      # First valid frame (allowing time to process previous two valid frames)
      packets.append(MiiPacket(
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (i%10, choose_small_frame_size(rand))],
          inter_frame_gap=2*packet_processing_time(46) + packet_processing_time(1518)
        ))

      # Take a copy to ensure that the original is not modified
      packet_copy = copy.deepcopy(packet)

      # Error frame after minimum IFG
      packet_copy.inter_frame_gap = ifg
      packets.append(packet_copy)

      # Second valid frame with minimum IFG
      packets.append(MiiPacket(
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (2 * ((i+1)%10), choose_small_frame_size(rand))],
          inter_frame_gap=ifg
        ))

    do_rx_test(impl, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed)

def runtest():
    random.seed(15)
    runall_rx(do_test)
