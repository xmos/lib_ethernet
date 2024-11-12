# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import Pyxsim as px
import os
import random
import sys
from pathlib import Path
import pytest

from mii_clock import Clock
from mii_phy import MiiReceiver
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import get_sim_args, create_if_needed, args
from helpers import get_mii_rx_clk_phy, get_mii_tx_clk_phy, get_rgmii_rx_clk_phy, get_rgmii_tx_clk_phy
from helpers import generate_tests


num_test_packets = 150

def start_test(phy):
    phy.num_packets = 0
    phy.num_bytes = 0
    phy.start_time = 0

def packet_checker(packet, phy):
    time_now = phy.xsi.get_time()

    # The CRC is not included in the packet bytes
    num_packet_bytes = len(packet.get_packet_bytes()) + 4

    clock = phy.get_clock()
    bit_time = clock.get_bit_time()

    if not phy.start_time:
        packet_time = num_packet_bytes * 8 * bit_time
        phy.start_time = time_now - packet_time

    phy.num_packets += 1
    phy.num_bytes += num_packet_bytes

    time_delta = time_now - phy.start_time
    mega_bits_per_second = (phy.num_bytes * 8.0) / time_delta * 1000

    if phy.num_packets > 1:
        efficiency = ((((phy.num_bytes * 8) + ((phy.num_packets - 1) * 96)) * bit_time) / time_delta) * 100
    else:
        efficiency = (((phy.num_bytes * 8) * bit_time) / time_delta) * 100

    print("Packet {} received; bytes: {}, ifg: {} => {:.2f} Mb/s, efficiency {:.2f}%".format(
        phy.num_packets, num_packet_bytes, packet.get_ifg(), mega_bits_per_second, efficiency))

    if phy.num_packets == num_test_packets:
        phy.xsi.terminate()


def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy):
    start_test(rx_phy)

    testname = 'test_time_tx'

    profile = f'{mac}_{tx_phy.get_name()}_{arch}'
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    with capfd.disabled():
        print(f"Running {testname}: {mac} {rx_phy.get_name()} phy at {rx_clk.get_name()} for {arch} arch")

    expect_folder = create_if_needed("expect_temp")
    expect_filename = f'{expect_folder}/{testname}_{mac}_{rx_phy.get_name()}_{rx_clk.get_name()}_{arch}.expect'
    create_expect(expect_filename)

    tester = px.testers.ComparisonTester(open(expect_filename), regexp=True)


    simargs = get_sim_args(testname, mac, rx_clk, rx_phy)

    result = px.run_on_simulator_(  binary,
                                    simthreads=[rx_clk, rx_phy, tx_clk, tx_phy],
                                    # tester=mytester(packets),
                                    tester=tester,
                                    simargs=simargs,
                                    capfd=capfd,
                                    do_xe_prebuild=False)

    assert result is True, f"{result}"


def create_expect(filename):
    """ Create the expect file for what packets should be reported by the DUT
    """
    with open(filename, 'w') as f:
        for i in range(num_test_packets):
            f.write("Packet \\d+ received; bytes: \\d+, ifg: \\d+\\.0 => \\d+\\.\\d+ Mb/s, efficiency \\d+\\.\\d+%\n")


test_params_file = Path(__file__).parent / "test_time_tx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_time_tx(capfd, params):
    verbose = False
      # Test 100 MBit - MII XS2
    if params["phy"] == "mii":
        (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=packet_checker)
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(do_timeout=False, verbose=verbose)
        do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_mii, tx_clk_25, tx_mii)

    elif params["phy"] == "rgmii":
        # Test 100 MBit - RGMII
        if params["clk"] == "25MHz":
            (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=packet_checker)
            (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, do_timeout=False, verbose=verbose)
            do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii)
        # Test 1000 MBit - RGMII
        elif params["clk"] == "125MHz":
            (rx_clk_125, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_125MHz, packet_fn=packet_checker)
            (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, do_timeout=False, verbose=verbose)
            do_test(capfd, params["mac"], params["arch"], rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii)
        else:
            assert 0, f"Invalid params: {params}"

    else:
        assert 0, f"Invalid params: {params}"
