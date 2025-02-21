# Copyright 2014-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
import copy
from mii_clock import Clock
from mii_packet import MiiPacket
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, run_parametrised_test_rx
import pytest
from pathlib import Path
from helpers import generate_tests
import warnings


def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed, rx_width=None, tx_width=None, hw_debugger_test=None):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()

    # Part A
    error_packets = []

    # Test Frame 1 - Fragments (no SFD, no valid CRC)
    max_fragment_len = 143
    if tx_clk.get_rate == Clock.CLK_125MHz:
        max_fragment_len = 142

    if tx_phy.get_name() == "rmii":
      if rx_width == "1b":
        min_fragment_length = 5 # https://github.com/xmos/lib_ethernet/issues/73
      else:
        min_fragment_length = 4
    else:
       min_fragment_length = 2

    # Incrememnt is meant to be 1, but for pragmatic reasons just test a subset of options (range(2, max_fragment_len, 1))
    for m in [min_fragment_length, max_fragment_len/3, max_fragment_len/2, max_fragment_len]:
      error_packets.append(MiiPacket(rand,
          num_preamble_nibbles=int(m), num_data_bytes=0,
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

    if hw_debugger_test is not None:
        hw_debugger_test(mac, arch, packets)
    else:
        do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed, override_dut_dir="test_rx", rx_width=rx_width, tx_width=tx_width)

test_params_file = Path(__file__).parent / "test_rx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_4_1_2(params, capfd):
    random.seed(12)
    run_parametrised_test_rx(capfd, do_test, params)
