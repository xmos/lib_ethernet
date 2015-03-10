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

    # Part A - maximum jabber size packet
    # Use a valid ether type as the type/len field can't encode the length
    ether_type_ip = [0x08, 0x00]

    # Jabber lengths as defined for 10Mb/s & 100Mb/s
    jabber_length = 9367
    if tx_clk.get_rate() == Clock.CLK_125MHz:
        # Length for 1000Mb/s
        jabber_length = 18742

    error_packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address,
        ether_len_type=ether_type_ip,
        num_preamble_nibbles=7,
        create_data_args=['step', (17, jabber_length)],
        dropped=True
      ))

    # Part B - Part A with valid frames before/after the errror frame
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
    random.seed(16)
    runall_rx(do_test)
