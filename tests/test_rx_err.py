#!/usr/bin/env python

import random
import copy
from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, runall_rx

def do_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    error_packets = []

    # Test that packets where the RXER line goes high are dropped even
    # if the rest of the packet is valid

    # Error on the first nibble of the preamble
    num_data_bytes = choose_small_frame_size(rand)
    error_packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address,
        num_data_bytes=num_data_bytes,
        error_nibbles=[0],
        dropped=True
      ))

    # Error somewhere in the middle of the packet
    num_data_bytes = choose_small_frame_size(rand)
    error_packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address,
        num_data_bytes=num_data_bytes,
        dropped=True
      ))
    packet = error_packets[-1]
    error_nibble = rand.randint(packet.num_preamble_nibbles + 1, len(packet.get_nibbles()))
    packet.error_nibbles = [error_nibble]

    # Due to BUG 16233 the RGMII code won't always detect an error in the last two bytes
    num_data_bytes = choose_small_frame_size(rand)
    error_packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address,
        num_data_bytes=num_data_bytes,
        dropped=True
      ))
    packet = error_packets[-1]
    packet.error_nibbles = [len(packet.get_nibbles()) - 5]

    # Now run all packets with valid frames before/after the errror frame to ensure the
    # errors don't interfere with valid frames
    packets = []
    for packet in error_packets:
        packets.append(packet)

    ifg = tx_clk.get_min_ifg()
    for i,packet in enumerate(error_packets):
      # First valid frame (allowing time to process previous two valid frames)
      packets.append(MiiPacket(rand,
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (i%10, choose_small_frame_size(rand))],
          inter_frame_gap=3*packet_processing_time(tx_phy, 46, mac)
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
    random.seed(19)
    runall_rx(do_test)
