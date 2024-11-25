import os
import sys
from pathlib import Path
import pytest
import Pyxsim as px

pkg_dir = Path(__file__).parent
def test_check_ifg_wait(capfd):
    testname = 'test_check_ifg_wait'
    binary = pkg_dir / testname / 'bin' / f'{testname}.xe'
    assert os.path.isfile(binary)
    expect_filename = pkg_dir / f'{testname}.expect'
    tester = px.testers.ComparisonTester(open(expect_filename))
    result = px.run_on_simulator_(  binary,
                                tester=tester,
                                do_xe_prebuild=False,
                                capfd=capfd)

    assert result is True, f"{result}"
