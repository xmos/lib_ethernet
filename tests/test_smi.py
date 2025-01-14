# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import Pyxsim as px
import pytest
import os
from pathlib import Path

from smi import smi_master_checker
from helpers import generate_tests, create_if_needed

def do_test(capfd, ptype, arch):
    testname = 'test_smi'

    with capfd.disabled():
        print(f"Running {testname}:port type {ptype}, arch {arch}")

    profile = f"{ptype}_{arch}"

    capfd.readouterr() # clear capfd buffer
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    tester = px.testers.ComparisonTester(open(f'{testname}.expect'))


    log_folder = create_if_needed("logs")
    filename = f"{log_folder}/xsim_trace_{testname}_{ptype}_{arch}"
    sim_args = ['--trace-to', f'{filename}.txt', '--enable-fnop-tracing']

    vcd_args = f'-o {filename}.vcd -tile tile[0] -ports -ports-detailed -instructions'
    vcd_args+= f' -functions -cycles -clock-blocks -pads'
    sim_args += ['--vcd-tracing', vcd_args]


    result = px.run_on_simulator_(  binary,
                                    simthreads=[smi_master_checker],
                                    tester=tester,
                                    simargs=sim_args,
                                    do_xe_prebuild=False,
                                    capfd=capfd
                                    )

    assert result is True, f"{result}"

test_params_file = Path(__file__).parent / "test_smi/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_link_status(capfd, params):
    verbose = False
   
    with capfd.disabled():  
        do_test(capfd, params["type"], params["arch"])

