#!/usr/bin/env python

import random
import copy
from mii_clock import Clock
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, runall_rx

def do_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    # Part A
    error_packets = []

    # Test Frame 1 - Fragments (no SFD, no valid CRC)
    max_fragment_len = 143
    if tx_clk.get_rate == Clock.CLK_125MHz:
        max_fragment_len = 142

    # Incrememnt is meant to be 1, but for pragmatic reasons just test a subset of options (range(2, max_fragment_len, 1))
    for m in [2, max_fragment_len/3, max_fragment_len/2, max_fragment_len]:
      error_packets.append(MiiPacket(rand,
          num_preamble_nibbles=m, num_data_bytes=0,
          sfd_nibble=None, dst_mac_addr=[], src_mac_addr=[], ether_len_type=[],
          send_crc_word=False,
          dropped=True
        ))

    # Test Frame 2 - Runts - undersized data with a valid CRC
    # NOTES:
    #  - Take 4 off the data length to leave room for the CRC
    #  - The data contents will be the DUT MAC address when long enough to contain a dst address
    # Incrememnt is meant to be 1, but for pragmatic reasons just test a subset of options (range(5, 45, 1))
    for n in [5, 25, 45]:
      error_packets.append(MiiPacket(rand,
          dst_mac_addr=[], src_mac_addr=[], ether_len_type=[],
          data_bytes=[(x & 0xff) for x in range(n - 4)],
          dropped=True
        ))

    # There should have been no errors logged by the MAC
    #controller.dumpStats()

    # Part B

    # Test Frame 5 - send a 7-octect preamble
    error_packets.append(MiiPacket(rand,
        num_preamble_nibbles=15, num_data_bytes=0,
        sfd_nibble=None, dst_mac_addr=[], src_mac_addr=[],
        ether_len_type=[], send_crc_word=False,
        dropped=True
      ))

    # Test Frame 6 - send a 7-octect preamble with SFD
    error_packets.append(MiiPacket(rand,
        num_preamble_nibbles=15, num_data_bytes=0,
        dst_mac_addr=[], src_mac_addr=[],
        ether_len_type=[], send_crc_word=False,
        dropped=True
      ))

    # Test Frame 7 - send a 7-octect preamble with SFD and dest MAC
    error_packets.append(MiiPacket(rand,
        num_preamble_nibbles=15, num_data_bytes=6,
        dst_mac_addr=dut_mac_address,
        src_mac_addr=[], ether_len_type=[], send_crc_word=False,
        dropped=True
      ))

    # Test Frame 8 - send a 7-octect preamble with SFD, dest and src MAC
    error_packets.append(MiiPacket(rand,
        num_preamble_nibbles=15, num_data_bytes=12,
        dst_mac_addr=dut_mac_address,
        ether_len_type=[], send_crc_word=False,
        dropped=True
      ))

    # There should have been no errors logged by the MAC
    #controller.dumpStats()

    # Part C
    # Don't support flow control - so don't run

    # Part D
    # Parts A & B with valid frames before/after the errror frame
    packets = []
    for packet in error_packets:
        packets.append(packet)

    ifg = tx_clk.get_min_ifg()
    for i,packet in enumerate(error_packets):
      # First valid frame (allowing time to process previous two valid frames)
      packets.append(MiiPacket(rand,
          dst_mac_addr=dut_mac_address,
          create_data_args=['step', (i%10, 46)],
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
          create_data_args=['step', (2 * ((i+1)%10), 46)],
          inter_frame_gap=ifg
        ))

    do_rx_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed)

def runtest():
    random.seed(12)
    runall_rx(do_test)
