# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import os
import sys
from pathlib import Path
import pytest
import Pyxsim as px
import random

from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address, check_received_packet
from helpers import get_sim_args, get_mii_tx_clk_phy, get_rgmii_tx_clk_phy
from helpers import generate_tests

def do_test(capfd, mac, arch, tx_clk, tx_phy, seed):
    testname = 'test_etype_filter'

    rand = random.Random()
    rand.seed(seed)

    profile = f'{mac}_{tx_phy.get_name()}_{arch}'
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    with capfd.disabled():
        print(f"Running {testname}: {tx_phy.get_name()} phy at {tx_clk.get_name()} (seed {seed})")

    dut_mac_address = get_dut_mac_address()
    packets = [
        MiiPacket(rand, dst_mac_addr=dut_mac_address, src_mac_addr=[0 for x in range(6)],
                  ether_len_type=[0x11, 0x11], data_bytes=[1,2,3,4] + [0 for x in range(50)]),
        MiiPacket(rand, dst_mac_addr=dut_mac_address, src_mac_addr=[0 for x in range(6)],
                  ether_len_type=[0x22, 0x22], data_bytes=[5,6,7,8] + [0 for x in range(60)])
      ]

    tx_phy.set_packets(packets)

    tester = px.testers.ComparisonTester(open('test_etype_filter.expect'), ordered=False)

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy)

    result = px.run_on_simulator_(  binary,
                                    simthreads=[tx_clk, tx_phy],
                                    tester=tester,
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    capfd=capfd)

    assert result is True, f"{result}"

test_params_file = Path(__file__).parent / "test_etype_filter/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_etype_filter(capfd, seed, params):
    if seed == None:
        seed = random.randint(0, sys.maxsize)


      # Test 100 MBit - MII XS2
    if params["phy"] == "mii":
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(verbose=True, test_ctrl="tile[0]:XS1_PORT_1A")
        do_test(capfd, params["mac"], params["arch"], tx_clk_25, tx_mii, seed)

    elif params["phy"] == "rgmii":
        # Test 100 MBit - RGMII
        if params["clk"] == "25MHz":
            (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, verbose=True, test_ctrl="tile[0]:XS1_PORT_1A")
            do_test(capfd, params["mac"], params["arch"], tx_clk_25, tx_rgmii, seed)
        # Test 1000 MBit - RGMII
        elif params["clk"] == "125MHz":
            (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, verbose=True, test_ctrl="tile[0]:XS1_PORT_1A")
            do_test(capfd, params["mac"], params["arch"], tx_clk_125, tx_rgmii, seed)
        else:
            assert 0, f"Invalid params: {params}"

    else:
        assert 0, f"Invalid params: {params}"
