# Copyright 2015-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import os
import sys
from pathlib import Path
import pytest
import random
import Pyxsim as px

from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address, args
from helpers import choose_small_frame_size, check_received_packet
from helpers import get_rgmii_tx_clk_phy, create_if_needed, get_sim_args
from helpers import generate_tests


initial_delay_us = 100000 * 1e6

class ClockControl(px.SimThread):
    """ A class to control the clocks, alternating between the 25 and 125 MHz clocks
        being active.
    """

    def __init__(self, speed_change_time, tx_clk_25, tx_rgmii_25, tx_clk_125, tx_rgmii_125):
        self.speed_change_time = speed_change_time
        self.tx_clk_25 = tx_clk_25
        self.tx_rgmii_25 = tx_rgmii_25
        self.tx_clk_125 = tx_clk_125
        self.tx_rgmii_125 = tx_rgmii_125

    def run(self):
        xsi = self.xsi

        # Setup the initial state (25MHz)
        self.tx_clk_25.start()
        self.tx_clk_125.stop()
        # Drive the status onto the data pins
        self.tx_rgmii_25.set_data(self.tx_rgmii_25._phy_status)


        # Change clock speeds 1/2 window before the packets
        self.wait_until(xsi.get_time() + initial_delay_us - (self.speed_change_time / 2))

        while True:
            # Wait for packets to be sent
            self.wait_until(xsi.get_time() + self.speed_change_time)

            # Go to 125MHz
            self.tx_clk_25.stop()
            self.tx_clk_125.start()
            self.tx_rgmii_125.set_data(self.tx_rgmii_125._phy_status)

            # Wait for packets to be sent
            self.wait_until(xsi.get_time() + self.speed_change_time)

            # Return to 25MHz
            self.tx_clk_25.start()
            self.tx_clk_125.stop()
            self.tx_rgmii_25.set_data(self.tx_rgmii_25._phy_status)


def create_packets(rand, clk, dut_mac_address, speed_change_time,
                   num_packets, initial_ifg, data_base):
    ifg = initial_ifg
    bit_time = clk.get_bit_time()

    packets = []

    for i in range(num_packets):
        packet = MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            create_data_args=['same', (data_base + i*2, choose_small_frame_size(rand))],
            inter_frame_gap=ifg
        )
        # The packet time includes its IFG, so discount that
        ifg = 2 * speed_change_time - (packet.get_packet_time(bit_time) - ifg)
        packets.append(packet)

    return packets


def do_test(capfd, mac, arch, tx_clk_25, tx_rgmii_25, tx_clk_125, tx_rgmii_125, seed):
    rand = random.Random()
    rand.seed(seed)

    # The time to run at each speed before switching to the other
    speed_change_time = 2000000 * 1e6

    testname = 'test_speed_change'

    profile = f'{mac}_rgmii_{arch}'
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    with capfd.disabled():
        print("Running {test}: rgmii phy (seed {seed})".format(test=testname, seed=seed))

    dut_mac_address = get_dut_mac_address()

    # The inter-frame gap is to give the DUT time to print its output
    packets_25 = create_packets(rand, tx_clk_25, dut_mac_address, speed_change_time,
                                1, 0, 0)
    packets_125 = create_packets(rand, tx_clk_125, dut_mac_address, speed_change_time,
                                 1, speed_change_time, 1)

    tx_rgmii_25.set_packets(packets_25)
    tx_rgmii_125.set_packets(packets_125)

    expect_folder = create_if_needed("expect_temp")
    expect_filename = f'{expect_folder}/{testname}_{mac}_rgmii_{arch}.expect'

    create_expect(expect_filename, packets_25, packets_125)
    tester = px.testers.ComparisonTester(open(expect_filename))

    clock_control = ClockControl(speed_change_time, tx_clk_25, tx_rgmii_25,
                                 tx_clk_125, tx_rgmii_125)

    simargs = get_sim_args(testname, mac, tx_clk_25, tx_rgmii_25)

    result = px.run_on_simulator_(  binary,
                                    simthreads=[tx_clk_25, tx_rgmii_25, tx_clk_125, tx_rgmii_125, clock_control],
                                    tester=tester,
                                    simargs=simargs,
                                    capfd=capfd,
                                    do_xe_prebuild=False)


    assert result is True, f"{result}"


def create_expect(filename, packets_25, packets_125):
    """ Create the expect file for what packets should be reported by the DUT
    """
    num_packets = 0
    num_data_bytes = 0
    for packet in packets_25 + packets_125:
        num_packets += 1
        num_data_bytes += len(packet.get_packet_bytes())

    with open(filename, 'w') as f:
        f.write("Received {} packets, {} bytes\n".format(num_packets, num_data_bytes))


test_params_file = Path(__file__).parent / "test_speed_change/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_speed_change(capfd, seed, params):
    if seed == None:
        seed = random.randint(0, sys.maxsize)


    verbose = False

    (tx_clk_25, tx_rgmii_25) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, initial_delay_us=initial_delay_us,
                                                  expect_loopback=False, verbose=verbose, dut_exit_time_us=(5 * px.Xsi.get_xsi_tick_freq_hz())/1e3)
    (tx_clk_125, tx_rgmii_125) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, initial_delay_us=initial_delay_us,
                                                      test_ctrl='tile[0]:XS1_PORT_1C',
                                                      expect_loopback=False, verbose=verbose, dut_exit_time_us=(5 * px.Xsi.get_xsi_tick_freq_hz())/1e3)

    do_test(capfd, params["mac"], params["arch"], tx_clk_25, tx_rgmii_25, tx_clk_125, tx_rgmii_125, seed)
