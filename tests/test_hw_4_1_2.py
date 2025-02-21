# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
import copy
from types import SimpleNamespace
from hw_helpers import mii2pcapfile, get_mac_address, calc_time_diff, hw_eth_debugger
from hardware_test_tools.XcoreApp import XcoreApp
from mii_clock import Clock
from mii_packet import MiiPacket
import pytest
import sys
from test_4_1_2 import do_test


def do_rx_test(mac, arch, packets):
    mii2pcapfile(packets)


def test_4_1_2_hw_debugger():
    random.seed(12)
    seed = random.randint(0, sys.maxsize)
    phy = SimpleNamespace(get_name=lambda: "rmii",
                          get_clock=lambda: SimpleNamespace(get_bit_time=lambda: 1))
    clock = SimpleNamespace(get_rate=Clock.CLK_50MHz,
                            get_min_ifg=lambda: 1e9)
    do_test(None, "rt_hp", "xs3", clock, phy, clock, phy, seed, hw_debugger_test=do_rx_test)

# def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed, rx_width=None, tx_width=None):