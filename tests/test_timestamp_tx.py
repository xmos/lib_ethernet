# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import Pyxsim as px
import os
from pathlib import Path
import pytest

from mii_clock import Clock
from mii_phy import MiiReceiver
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import get_sim_args
from helpers import get_mii_rx_clk_phy, get_rgmii_rx_clk_phy
from helpers import get_mii_tx_clk_phy, get_rgmii_tx_clk_phy
from helpers import generate_tests

def packet_checker(packet, phy):
    # Ignore the CRC bytes (-4)
    data = packet.data_bytes[:-4]

    if len(data) < 2:
        print(f"ERROR: packet doesn't contain enough data ({len(data)} bytes)")
        return

    step = data[1] - data[0]

    for i in range(len(data)-1):
        x = data[i+1] - data[i]
        x = x & 0xff;
        if x != step:
            print(f"ERROR: byte {i+1} is {x} more than byte {i} (expected {step}).")
            # Only print one error per packet
            break

def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy):
    testname = 'test_timestamp_tx'

    profile = f'{mac}_{tx_phy.get_name()}_{arch}'
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    with capfd.disabled():
        print(f"Running {testname}: {mac} {rx_phy.get_name()} phy at {rx_clk.get_name()}, {arch} arch")

    tester = px.testers.ComparisonTester(open(f'{testname}.expect'), regexp=True)

    simargs = get_sim_args(testname, mac, rx_clk, rx_phy)

    result = px.run_on_simulator_(  binary,
                                    simthreads=[rx_clk, rx_phy, tx_clk, tx_phy],
                                    tester=tester,
                                    simargs=simargs,
                                    capfd=capfd,
                                    do_xe_prebuild=False)

    assert result is True, f"{result}"

test_params_file = Path(__file__).parent / "test_timestamp_tx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_timestamp_tx(capfd, params):
    # Even though this is a TX-only test, both PHYs are needed in order to drive the mode pins for RGMII

    verbose = False

    # Test 100 MBit - MII XS2
    if params["phy"] == "mii":
        (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=packet_checker, verbose=verbose, test_ctrl='tile[0]:XS1_PORT_1C')
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(dut_exit_time=200000 * 1e6)
        do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_mii, tx_clk_25, tx_mii)

    elif params["phy"] == "rgmii":
        # Test 100 MBit - RGMII
        if params["clk"] == "25MHz":
            (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=packet_checker, test_ctrl='tile[0]:XS1_PORT_1C')
            (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, dut_exit_time=200000 * 1e6)
            do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii)
        # Test 1000 MBit - RGMII
        elif params["clk"] == "125MHz":
            (rx_clk_125, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_125MHz, packet_fn=packet_checker, verbose=verbose, test_ctrl='tile[0]:XS1_PORT_1C')
            (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, dut_exit_time=300000 * 1e6)
            do_test(capfd, params["mac"], params["arch"], rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii)
        else:
            assert 0, f"Invalid params: {params}"

    else:
        assert 0, f"Invalid params: {params}"
