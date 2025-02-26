# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

# Debugger hardware version of sim test

from hw_helpers import hw_4_1_x_test_init, do_hw_dbg_rx_test
from test_4_2_6 import do_test


def test_4_2_6_hw_debugger(request):
    seed, testname, mac, arch, phy, clock = hw_4_1_x_test_init(26)
    do_test(None, mac, arch, clock, phy, clock, phy, seed, hw_debugger_test=(do_hw_dbg_rx_test, request, testname))
