# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import Pyxsim as px
import pytest
import os
import random
import sys
from pathlib import Path

from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver
from mii_packet import MiiPacket
from helpers import get_sim_args, get_mii_tx_clk_phy, get_rgmii_tx_clk_phy
from helpers import generate_tests


def do_test(capfd, mac, arch, tx_clk, tx_phy):
    testname = 'test_link_status'

    with capfd.disabled():
        print(f"Running {testname}: {mac} {tx_phy.get_name()} phy, {arch} arch at {tx_clk.get_name()}")
    capfd.readouterr() # clear capfd buffer

    profile = f'{mac}_{tx_phy.get_name()}_{arch}'
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    tester = px.testers.ComparisonTester(open(f'{testname}.expect'))

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy, arch=arch)
    result = px.run_on_simulator_(  binary,
                                    simthreads=[tx_clk, tx_phy],
                                    tester=tester,
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    capfd=capfd)

    assert result is True, f"{result}"

test_params_file = Path(__file__).parent / "test_link_status/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_link_status(capfd, params):
    # Test 100 MBit - MII XS2
    if params["phy"] == "mii":
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(test_ctrl='tile[0]:XS1_PORT_1C')
        do_test(capfd, params["mac"], params["arch"], tx_clk_25, tx_mii)

    elif params["phy"] == "rgmii":
        # Test 100 MBit - RGMII
        if params["clk"] == "25MHz":
            (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, test_ctrl='tile[0]:XS1_PORT_1C')
            do_test(capfd, params["mac"], params["arch"], tx_clk_25, tx_rgmii)
        # Test 1000 MBit - RGMII
        elif params["clk"] == "125MHz":
            (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, test_ctrl='tile[0]:XS1_PORT_1A')
            do_test(capfd, params["mac"], params["arch"], tx_clk_125, tx_rgmii)
        else:
            assert 0, f"Invalid params: {params}"

    else:
        assert 0, f"Invalid params: {params}"

