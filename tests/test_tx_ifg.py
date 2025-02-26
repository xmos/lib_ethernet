# Copyright 2014-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import Pyxsim as px
import os
from pathlib import Path
import pytest

from mii_clock import Clock
from mii_phy import MiiReceiver
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import get_sim_args, create_if_needed, args
from helpers import get_mii_rx_clk_phy, get_mii_tx_clk_phy, get_rgmii_rx_clk_phy, get_rgmii_tx_clk_phy
from helpers import get_rmii_clk, get_rmii_rx_phy
from helpers import generate_tests
from collections import defaultdict
from hw_helpers import log_ifg_summary


num_test_packets = (1514-60+1)*2 # 2 packets for each valid payload length. Takes about 15mins to run in sim

class IfgTester:
    def __init__(self):
        self.result = None

    def run(self, output):
        timestamps = output[0::2]
        lengths = output[1::2]
        timestamps = list(map(int, timestamps))
        lengths = list(map(int, lengths))
        iters = min(len(lengths), len(timestamps))
        overhead = 8 + 4 # preamble and crc
        line_speed = 100e6

        ifg_full_dict = defaultdict(list)
        for i in range(iters - 1):
            ts_diff = (timestamps[i+1] - timestamps[i]) % (1 << 32)
            packet_length = lengths[i] + overhead
            packet_time_ns = (1e9 * 8*packet_length)/line_speed
            ts_diff_ns = ts_diff * 10 # ref timer is 10ns
            ifg = ts_diff_ns - packet_time_ns
            ifg_full_dict[lengths[i]].append(round(ifg, 2))
        if len(ifg_full_dict):
            log_ifg_summary(ifg_full_dict,
                ifg_summary_file="ifg_sweep_summary_sim_device_probe.txt",
                ifg_full_file="ifg_sweep_full_sim_device_probe.txt"
                )

        return True

def start_test(phy, test_type):
    phy.num_packets = 0
    phy.num_bytes = 0
    phy.start_time = 0
    phy.ifg_full_dict = defaultdict(list) # dictionary containing IFGs seen for each payload length
    phy.test_type = test_type

def packet_checker(packet, phy):
    # The CRC is not included in the packet bytes
    num_packet_bytes = len(packet.get_packet_bytes()) + 4
    phy.num_packets += 1
    phy.num_bytes += num_packet_bytes

    if phy.num_packets > 1:
        phy.ifg_full_dict[num_packet_bytes].append(round(packet.get_ifg()/1e6, 2))


    if phy.num_packets == num_test_packets:
        if "probe" in phy.test_type:
            log_ifg_summary(phy.ifg_full_dict,
                            ifg_summary_file="ifg_sweep_summary_sim_host_probe.txt",
                            ifg_full_file="ifg_sweep_full_sim_host_probe.txt"
                            )
        else:
            log_ifg_summary(phy.ifg_full_dict,
                ifg_summary_file="ifg_sweep_summary_sim_host_no_probe.txt",
                ifg_full_file="ifg_sweep_full_sim_host_no_probe.txt"
                )
        poll_duration_us = 10
        poll_duration_ticks = (poll_duration_us* px.Xsi.get_xsi_tick_freq_hz())/1e6
        phy.wait_until(phy.xsi.get_time() + poll_duration_ticks) # If the device is printing probe timestamps wait for them to come thrpugh
        phy.xsi.terminate()


def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, tx_width=None, test_type=None):
    start_test(rx_phy, test_type)

    testname = 'test_tx_ifg'

    if tx_width:
        profile = f'{mac}_{test_type}_tx{tx_width}_{arch}'
        with capfd.disabled():
            print(f"Running {testname}: {mac} {test_type} phy, {tx_width} tx_width at {rx_clk.get_name()} for {arch} arch")
    else:
        profile = f'{mac}_{test_type}_{arch}'
        with capfd.disabled():
            print(f"Running {testname}: {mac} {test_type} phy at {rx_clk.get_name()} for {arch} arch")

    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    simargs = get_sim_args(testname, mac, rx_clk, rx_phy)

    simthreads = [rx_clk, rx_phy]
    if tx_clk != None:
        simthreads.append(tx_clk)
    if tx_phy != None:
        simthreads.append(tx_phy)

    tester = IfgTester()

    result = px.run_on_simulator_(  binary,
                                    simthreads=simthreads,
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    timeout=20*60,
                                    tester=tester,
                                    capfd=capfd)

    assert result is True, f"{result}"


test_params_file = Path(__file__).parent / "test_tx_ifg/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_tx_ifg(capfd, params):
    verbose = False
    if "rmii" in params["phy"]:
        clk = get_rmii_clk(Clock.CLK_50MHz)
        rx_rmii_phy = get_rmii_rx_phy(params['tx_width'],
                                        clk,
                                        packet_fn=packet_checker,
                                        verbose=verbose
                                    )

        do_test(capfd, params["mac"], params["arch"], clk, rx_rmii_phy, None, None, tx_width=params['tx_width'], test_type = params["phy"])
    else:
        assert 0, f"Invalid params: {params}"
