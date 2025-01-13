# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import Pyxsim as px
import pytest
import os
from pathlib import Path

from smi import smi_master_checker
from helpers import generate_tests

def do_test(capfd):
    testname = 'test_smi'

    with capfd.disabled():
        print(f"Running {testname}: {mac} {tx_phy.get_name()} phy, {arch} arch at {tx_clk.get_name()}")


    capfd.readouterr() # clear capfd buffer
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    tester = px.testers.ComparisonTester(open(f'{testname}.expect'))
    simargs = get_sim_args(testname, mac, tx_clk, tx_phy, arch=arch)

    result = px.run_on_simulator_(  binary,
                                    simthreads=[tx_clk, tx_phy],
                                    tester=tester,
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    capfd=capfd
                                    )

    assert result is True, f"{result}"

test_params_file = Path(__file__).parent / "test_smi/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_link_status(capfd, params):
    verbose = False
   
    rmii_clk = get_rmii_clk(Clock.CLK_50MHz)
    tx_rmii_phy = get_rmii_tx_phy(params['rx_width'],
                                  rmii_clk,
                                      verbose=verbose,
                                      test_ctrl="tile[0]:XS1_PORT_1M"
                                    )

    do_test(capfd, params["mac"], params["arch"], rmii_clk, tx_rmii_phy, params["rx_width"])

