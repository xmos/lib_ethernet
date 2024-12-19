# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
import Pyxsim as px
from pathlib import Path
import pytest
import sys

from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address, packet_processing_time_clock_cycles
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


def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed, rx_width=None, tx_width=None):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()
    broadcast_mac_address = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff]

    # The inter-frame gap is to give the DUT time to print its output
    packets = []

    for mac_address in [dut_mac_address, broadcast_mac_address]:
        packets.append(MiiPacket(rand,
            dst_mac_addr=mac_address,
            create_data_args=['step', (1, 72)]
          ))

        packets.append(MiiPacket(rand,
            dst_mac_addr=mac_address,
            create_data_args=['step', (5, 52)],
            inter_frame_gap=packet_processing_time(tx_phy, 72, mac),
          ))

        packets.append(MiiPacket(rand,
            dst_mac_addr=mac_address,
            create_data_args=['step', (7, 1500)],
            inter_frame_gap=packet_processing_time(tx_phy, 52, mac),
          ))


    # Send enough basic frames to ensure the buffers in the DUT have wrapped

    for i in range(15):
        packets.append(MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (i, 1500)],
            inter_frame_gap=packet_processing_time(tx_phy, 1500, mac),
        ))


    do_error = True

    # The gigabit RGMII can't handle spurious errors
    if tx_clk.get_rate() == Clock.CLK_125MHz:
        do_error = False

    error_driver = TxError(tx_phy, do_error)

    do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed, extra_tasks=[error_driver], rx_width=rx_width, tx_width=tx_width)

test_params_file = Path(__file__).parent / "test_rx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_rx(capfd, seed, params):
    with capfd.disabled():
        print(params)

    if seed == None:
        seed = random.randint(0, sys.maxsize)

    run_parametrised_test_rx(capfd, do_test, params, seed=seed)
