# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import Pyxsim as px
import pytest
import os
from pathlib import Path

from smi import smi_master_checker, smi_make_packet
from helpers import generate_tests, create_if_needed


def do_test(capfd, ptype, arch):
    testname = 'test_smi'

    with capfd.disabled():
        print(f"Running {testname}:port type {ptype}, arch {arch}")

    profile = f"{ptype}_{arch}"

    capfd.readouterr() # clear capfd buffer
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    tester = px.testers.ComparisonTester(open(f'{testname}.expect'), regexp=True, ordered=False)

    log_folder = create_if_needed("logs")
    filename = f"{log_folder}/xsim_trace_{testname}_{ptype}_{arch}"
    sim_args = ['--trace-to', f'{filename}.txt', '--enable-fnop-tracing']

    vcd_args = f'-o {filename}.vcd -tile tile[0] -ports -ports-detailed -instructions'
    vcd_args+= f' -functions -cycles -clock-blocks -pads'
    sim_args += ['--vcd-tracing', vcd_args]

    if "single" in ptype:
        mdc_port = "tile[0]:XS1_PORT_4B.0"
        mdio_port = "tile[0]:XS1_PORT_4B.1"
    else:
        mdc_port = "tile[0]:XS1_PORT_1N"
        mdio_port = "tile[0]:XS1_PORT_1M"
    rst_n_port = "tile[0]:XS1_PORT_4A"
    expected_speed_hz = 1.666667e6

    smi_harness = smi_master_checker(mdc_port, mdio_port, rst_n_port, expected_speed_hz, [0x1234, 0xaaaa, 0x4321])
    result = px.run_on_simulator_(  binary,
                                    simthreads=[smi_harness],
                                    tester=tester,
                                    simargs=sim_args,
                                    do_xe_prebuild=False,
                                    capfd=capfd
                                    )

    assert result is True, f"{result}"

test_params_file = Path(__file__).parent / "test_smi/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_smi(capfd, params):
   
    # For debug
    # with capfd.disabled():
    #     do_test(capfd, params["type"], params["arch"])
    do_test(capfd, params["type"], params["arch"])
