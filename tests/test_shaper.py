# Copyright 2015-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import pytest
from pathlib import Path
import Pyxsim as px
import os
import sys

from mii_clock import Clock
from mii_phy import MiiReceiver
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import get_sim_args, create_if_needed, args
from helpers import get_mii_rx_clk_phy, get_rgmii_rx_clk_phy
from helpers import get_mii_tx_clk_phy, get_rgmii_tx_clk_phy
from helpers import generate_tests


high_priority_mac_addr = [0, 1, 2, 3, 4, 5]

def packet_checker(packet, phy):
    if phy._verbose:
        sys.stdout.write(packet.dump())
    if packet.dst_mac_addr == high_priority_mac_addr:
        if phy._verbose: print(f"HP recvd time {phy.xsi.get_time()/1e6} ns")
        phy.n_hp_packets += 1
        done = phy.timeout_monitor.hp_packet_received()
        if done:
            if phy.n_hp_packets >= phy.n_lp_packets:
                print(f"ERROR: Only {phy.n_lp_packets} low priority packets received vs {phy.n_hp_packets} high priority")
            phy.xsi.terminate()
    else:
        if phy._verbose: print(f"LP recvd time {phy.xsi.get_time()/1e6} ns")
        phy.n_lp_packets += 1


class TimeoutMonitor(px.SimThread):

    def __init__(self, initial_delay, packet_period, expect_count, verbose):
        self._seen_packets = 0
        self._initial_delay = initial_delay
        self._packet_period = packet_period
        self._expect_count = expect_count
        self._packet_count = 0
        self._verbose = verbose

    def hp_packet_received(self):
        xsi = self.xsi

        self._packet_count += 1
        self._seen_packets += 1
        print(f"{xsi.get_time()/1e6}: Received HP packet {self._packet_count}")
        if self._verbose:
            print(f"{xsi.get_time()/1e6} ns: HP seen_packets {self._seen_packets}")

        max_conscutive_hp_pckts = 2
        if self._seen_packets > max_conscutive_hp_pckts:
            print(f"ERROR: More than {max_conscutive_hp_pckts} HP packets seen in time period")
            return True

        if self._packet_count == self._expect_count:
            print("DONE")
            return True

        return False

    def run(self):
        xsi = self.xsi

        self.wait_until(xsi.get_time() + self._initial_delay)

        while True:
            self.wait_until(xsi.get_time() + self._packet_period)
            self._seen_packets -= 1

            if self._verbose:
                print(f"{xsi.get_time()}: seen_packets {self._seen_packets}")

            if self._seen_packets < -1:
                print("ERROR: More than 2 periods without packets seen")
                xsi.terminate()


def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy):
    testname = 'test_shaper'
    mii_clk_name = "125MHz" if "125" in tx_clk.get_name() else "25MHz" # Fix issue with lower case h
    profile = f'{mac}_{tx_phy.get_name()}_{mii_clk_name}_{arch}'
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    with capfd.disabled():
        print(f"Running {testname}: {rx_phy.get_name()} phy at {tx_clk.get_name()} binary: {binary}")

    # MAC request 5Mb/s
    slope = 5 * 1024 * 1024

    bit_time = tx_phy.get_clock().get_bit_time()
    bit_rate = 1e15 / bit_time
    data_bytes = 100
    ifg_bytes = 96/8
    preamble_bytes = 8
    crc_bytes = 4
    packet_bytes = ifg_bytes + preamble_bytes + data_bytes + crc_bytes
    packet_bits = packet_bytes * 8
    packets_per_second = slope / packet_bits
    packet_period_fs = 1e15 / packets_per_second

    with capfd.disabled():
        print(f"Running with {data_bytes} byte packets (total {packet_bits} bits), {slope} bps requested, packet period {packet_period_fs/1e9:.2f} us, wire rate: {bit_rate/1e6}Mbps")

    num_expected_packets = 30
    initial_delay_us = 55 # To allow DUT ethernet to come up and start transmitting
    timeout_monitor = TimeoutMonitor(initial_delay_us * 1e9, packet_period_fs, num_expected_packets, False)
    rx_phy.timeout_monitor = timeout_monitor
    rx_phy.n_hp_packets = 0
    rx_phy.n_lp_packets = 0

    expect_folder = create_if_needed("expect_temp")
    expect_filename = f'{expect_folder}/{testname}_{mac}_{tx_phy.get_name()}_{tx_clk.get_name()}_{arch}.expect'

    create_expect(expect_filename, num_expected_packets)
    tester = px.testers.ComparisonTester(open(expect_filename), regexp=True)

    simargs = get_sim_args(testname, mac, rx_clk, rx_phy)

    if rx_phy.get_name() == 'rgmii' and rx_clk.get_name() == '125Mhz':
        result = px.run_on_simulator_(  binary,
                                        simthreads=[rx_clk, rx_phy, tx_clk, tx_phy, timeout_monitor],
                                        tester=tester,
                                        simargs=simargs,
                                        do_xe_prebuild=False,
                                        capfd=capfd,
                                        timeout=1200)
    else:
        result = px.run_on_simulator_(  binary,
                                        simthreads=[rx_clk, rx_phy, tx_clk, tx_phy, timeout_monitor],
                                        tester=tester,
                                        simargs=simargs,
                                        capfd=capfd,
                                        do_xe_prebuild=False)


    assert result is True, f"{result}"


def create_expect(filename, num_expected_packets):
    """ Create the expect file for what packets should be reported by the DUT
    """
    with open(filename, 'w') as f:
        for i in range(num_expected_packets):
            f.write("\\d+.?\\d*: Received HP packet {}\n".format(i + 1))
        f.write("DONE\n")

test_params_file = Path(__file__).parent / "test_shaper/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_rx_err(capfd, params):
    # Even though this is a TX-only test, both PHYs are needed in order to drive the mode pins for RGMII

    verbose = False

    # Test 100 MBit - MII XS2
    if params["phy"] == "mii":
        (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=packet_checker, verbose=verbose)
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(do_timeout=False)
        do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_mii, tx_clk_25, tx_mii)

    elif params["phy"] == "rgmii":
        # Test 100 MBit - RGMII
        if params["clk"] == "25MHz":
            (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=packet_checker, verbose=verbose)
            (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, do_timeout=False)
            do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii)
        # Test 1000 MBit - RGMII
        elif params["clk"] == "125MHz":
            (rx_clk_125, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_125MHz, packet_fn=packet_checker, verbose=verbose)
            (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, do_timeout=False)
            do_test(capfd, params["mac"], params["arch"], rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii)
        else:
            assert 0, f"Invalid params: {params}"

    else:
        assert 0, f"Invalid params: {params}"
