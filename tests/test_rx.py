#!/usr/bin/env python

import random
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, runall_rx

def do_test(mac, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    # The inter-frame gap is to give the DUT time to print its output
    packets = [
        MiiPacket(
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (1, 72)]
          ),

        MiiPacket(
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (5, 52)],
            inter_frame_gap=packet_processing_time(tx_phy, 72, mac)
          ),

        MiiPacket(
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (7, 1500)],
            inter_frame_gap=packet_processing_time(tx_phy, 52, mac)
          )
      ]

    do_rx_test(mac, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed, 'smoke')

def runtest():
    random.seed(1)
    runall_rx(do_test)
