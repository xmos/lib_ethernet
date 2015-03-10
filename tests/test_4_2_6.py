#!/usr/bin/env python

import random
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, runall_rx

def do_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    packets = []

    ifg = tx_clk.get_min_ifg()

    # Part A - Ensure that two packets separated by minimum IFG are received ok
    packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address,
        create_data_args=['step', (rand.randint(1, 254), choose_small_frame_size(rand))]
      ))
    packets.append(MiiPacket(rand,
        dst_mac_addr=dut_mac_address,
        create_data_args=['step', (rand.randint(1, 254), choose_small_frame_size(rand))],
        inter_frame_gap=ifg
      ))

    # Part B - Determine the minimum IFG that can be supported
    bit_time = ifg/96

    # Allow lots of time for the DUT to recover between test bursts
    recovery_time = 4*packet_processing_time(tx_phy, 46, mac)

    # Test shrinking the IFG by different amounts. Use the shrink as the step for debug purposes
    for gap_shrink in [5, 10]:
        new_ifg = ifg - gap_shrink * bit_time

        packets.append(MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (gap_shrink, choose_small_frame_size(rand))],
            inter_frame_gap=recovery_time
          ))
        packets.append(MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (gap_shrink, choose_small_frame_size(rand))],
            inter_frame_gap=new_ifg
          ))

    do_rx_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed)

def runtest():
    random.seed(26)
    runall_rx(do_test)
