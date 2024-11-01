# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
import Pyxsim as px
import json
from pathlib import Path
import pytest

from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, run_parametrised_test_rx

with open(Path(__file__).parent / "test_tx/test_params.json") as f:
    params = json.load(f)

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


def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed):
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
            inter_frame_gap=packet_processing_time(tx_phy, 72, mac)
          ))

        packets.append(MiiPacket(rand,
            dst_mac_addr=mac_address,
            create_data_args=['step', (7, 1500)],
            inter_frame_gap=packet_processing_time(tx_phy, 52, mac)
          ))

    # Send enough basic frames to ensure the buffers in the DUT have wrapped
    for i in range(11):
        packets.append(MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (i, 1500)],
            inter_frame_gap=packet_processing_time(tx_phy, 1500, mac)
        ))

    do_error = True

    # The gigabit RGMII can't handle spurious errors
    if tx_clk.get_rate() == Clock.CLK_125MHz:
        do_error = False

    error_driver = TxError(tx_phy, do_error)

    do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed,
               level='smoke', extra_tasks=[error_driver])

# @pytest.mark.parametrize("params", params["PROFILES"], ids=["-".join(list(profile.values())) for profile in params["PROFILES"]])
@pytest.mark.parametrize("params", [{'phy': 'mii', 'clk': '25MHz', 'mac': 'rt', 'arch': 'xs2'}])
def test_rx(capfd, params):
    print(params)
    random.seed(1)
    run_parametrised_test_rx(capfd, do_test, params)
