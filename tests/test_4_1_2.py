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
    
    # Part A
    error_packets = []

    # Test Frame 1 - Fragments (no SFD, no valid CRC)
    max_fragment_len = 143
    if clk.get_rate == Clock.CLK_125MHz:
        max_fragment_len = 142

    # Incrememnt is meant to be 1, but for pragmatic reasons just test a subset of options (range(2, max_fragment_len, 1))
    for m in [2, max_fragment_len/3, max_fragment_len/2, max_fragment_len]:
      error_packets.append(MiiPacket(num_preamble_nibbles=m, num_data_bytes=0,
                               sfd_nibble=None, dst_mac_addr=[], src_mac_addr=[], ether_len_type=[],
                               send_crc_word=False))

    # Test Frame 2 - Runts - undersized data with a valid CRC
    # NOTES:
    #  - Take 4 off the data length to leave room for the CRC
    #  - The data contents will be the DUT MAC address when long enough to contain a dst address
    # Incrememnt is meant to be 1, but for pragmatic reasons just test a subset of options (range(5, 45, 1))
    for n in [5, 25, 45]:
      error_packets.append(MiiPacket(dst_mac_addr=[], src_mac_addr=[], ether_len_type=[],
                                     data_bytes=[(x & 0xff) for x in range(n - 4)]))

    # There should have been no errors logged by the MAC
    #controller.dumpStats()

    # Part B

    # Test Frame 5 - send a 7-octect preamble
    error_packets.append(MiiPacket(num_preamble_nibbles=7, num_data_bytes=0,
                             sfd_nibble=None, dst_mac_addr=[], src_mac_addr=[],
                             ether_len_type=[], send_crc_word=False))
        
    # Test Frame 6 - send a 7-octect preamble with SFD
    error_packets.append(MiiPacket(num_preamble_nibbles=7, num_data_bytes=0,
                             dst_mac_addr=[], src_mac_addr=[],
                             ether_len_type=[], send_crc_word=False))
        
    # Test Frame 7 - send a 7-octect preamble with SFD and dest MAC
    error_packets.append(MiiPacket(num_preamble_nibbles=7, num_data_bytes=6,
                             dst_mac_addr=dut_mac_address,
                             src_mac_addr=[], ether_len_type=[], send_crc_word=False))
        
    # Test Frame 8 - send a 7-octect preamble with SFD, dest and src MAC
    error_packets.append(MiiPacket(num_preamble_nibbles=7, num_data_bytes=12,
                             dst_mac_addr=dut_mac_address,
                             ether_len_type=[], send_crc_word=False))
        
    # There should have been no errors logged by the MAC
    #controller.dumpStats()

    # Part C
    # Don't support flow control - so don't run

    # Part D
    # Parts A & B with valid frames before/after the errror frame
    packets = []
    for packet in error_packets:
        packets.append(packet)

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
