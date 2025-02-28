# Copyright 2014-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import os
import sys
from pathlib import Path
import pytest

import Pyxsim as px
from mii_clock import Clock
from mii_phy import MiiReceiver
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import get_sim_args
from helpers import get_mii_rx_clk_phy, get_rgmii_rx_clk_phy
from helpers import get_mii_tx_clk_phy, get_rgmii_tx_clk_phy
from helpers import get_rmii_clk, get_rmii_rx_phy
from helpers import generate_tests

def packet_checker(packet, phy, test_ctrl):
    print("Packet received:")
    sys.stdout.write(packet.dump(show_ifg=False))

    # Ignore the CRC bytes (-4)
    data = packet.data_bytes[:-4]

    if len(data) < 2:
        print(f"ERROR: packet doesn't contain enough data ({len(data)} bytes)")
        return

    step = data[1] - data[0]
    print(f"Step = {step}.")

    for i in range(len(data)-1):
        x = data[i+1] - data[i]
        x = x & 0xff;
        if x != step:
            print(f"ERROR: byte {i+1} is {x} more than byte %d (expected {step}).")
            # Only print one error per packet
            break

def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, tx_width=None):
    testname = 'test_tx'

    if tx_width:
        profile = f'{mac}_{rx_phy.get_name()}_tx{tx_width}_{arch}'
        with capfd.disabled():
            print(f"Running {testname}: {mac} {rx_phy.get_name()} phy, {tx_width} tx_width, {arch} arch at {rx_clk.get_name()}")
    else:
        profile = f'{mac}_{rx_phy.get_name()}_{arch}'
        with capfd.disabled():
            print(f"Running {testname}: {mac} {rx_phy.get_name()} phy, {arch} arch at {rx_clk.get_name()}")

    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    capfd.readouterr() # clear capfd buffer

    tester = px.testers.ComparisonTester(open(f'{testname}.expect'))

    simargs = get_sim_args(testname, mac, rx_clk, rx_phy)

    simthreads = [rx_clk, rx_phy]
    if tx_clk != None:
        simthreads.append(tx_clk)
    if tx_phy != None:
        simthreads.append(tx_phy)

    result = px.run_on_simulator_(  binary,
                                    simthreads=simthreads,
                                    tester=tester,
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    capfd=capfd
                                    )

    assert result is True, f"{result}"


test_params_file = Path(__file__).parent / "test_tx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_tx(capfd, params):
    # Even though this is a TX-only test, both PHYs are needed in order to drive the mode pins for RGMII
    # Test 100 MBit - MII XS2
    if params["phy"] == "mii":
        (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=packet_checker, test_ctrl='tile[0]:XS1_PORT_1C')
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(do_timeout=False)
        do_test(capfd, params["mac"], params['arch'], rx_clk_25, rx_mii, tx_clk_25, tx_mii)

    elif params["phy"] == "rgmii":
        # Test 100 MBit - RGMII
        if params["clk"] == "25MHz":
            (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=packet_checker, test_ctrl='tile[0]:XS1_PORT_1C')
            (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, do_timeout=False)
            do_test(capfd, params["mac"], params['arch'], rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii)
        # Test 1000 MBit - RGMII
        elif params["clk"] == "125MHz":
            (rx_clk_125, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_125MHz, packet_fn=packet_checker, test_ctrl='tile[0]:XS1_PORT_1C')
            (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, do_timeout=False)
            do_test(capfd, params["mac"], params['arch'], rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii)
        else:
            assert 0, f"Invalid params: {params}"
    elif params["phy"] == "rmii":
        test_ctrl='tile[0]:XS1_PORT_1M'
        verbose = False

        clk = get_rmii_clk(Clock.CLK_50MHz)
        rx_rmii_phy = get_rmii_rx_phy(params['tx_width'],
                                        clk,
                                        packet_fn=packet_checker,
                                        verbose=verbose,
                                        test_ctrl=test_ctrl
                                    )
        do_test(capfd, params["mac"], params["arch"], clk, rx_rmii_phy, None, None, tx_width=params['tx_width'])
    else:
        assert 0, f"Invalid params: {params}"
