# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
import Pyxsim as px
from pathlib import Path
import pytest
import sys

from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, run_parametrised_test_rx
from helpers import generate_tests

class TxError(px.SimThread):

    def __init__(self, tx_phy, do_error):
        self._tx_phy = tx_phy
        self._do_error = do_error
        self._initial_delay = tx_phy._initial_delay - 5000*1e6

    def run(self):
        xsi = self.xsi

        if not self._do_error:
            return

        self.wait_until(xsi.get_time() + self._initial_delay)
        self._tx_phy.drive_error(1)
        self.wait_until(xsi.get_time() + 100*1e6)
        self._tx_phy.drive_error(0)

"""
This runs the device at 350MHz with 5 threads so max 70MHz per thread which gives us a little
headroom for a typical operating rate of 600MHz with 8 threads (75MHz min)
rx1b and rx4b are the hardest cases. CUrrently these break at 300MHz (310 OK) so we are well withing timing
"""
def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed, rx_width=None, tx_width=None):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()
    broadcast_mac_address = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff]

    packets = []

    # Send frames which excercise all of the tail length vals (0, 1, 2, 3 bytes)
    packet_start_len = 100
    for i in range(5): 
        packets.append(MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (i, packet_start_len)],
            inter_frame_gap=packet_processing_time(tx_phy, packet_start_len, mac),
        ))

    do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed, rx_width=rx_width, tx_width=tx_width)

test_params_file = Path(__file__).parent / "test_rmii_timing/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_rx(capfd, seed, params):
    with capfd.disabled():
        print(params)

    if seed == None:
        seed = random.randint(0, sys.maxsize)

    run_parametrised_test_rx(capfd, do_test, params, seed=seed)
