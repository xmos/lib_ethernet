# Copyright 2018-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import random
import Pyxsim as px
from pathlib import Path
import pytest
import re
import sys
import os

from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import get_sim_args, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, args
from helpers import get_mii_rx_clk_phy, get_mii_tx_clk_phy, get_rgmii_rx_clk_phy, get_rgmii_tx_clk_phy
from helpers import generate_tests
from helpers import get_rmii_clk, get_rmii_tx_phy

class OutputChecker():
    """ Check that every line from the DUT is an increasing packet size received
    """

    def __init__(self, test, config={}):
        self._test = test
        self._config = config
        print("INIT OutputChecker", file=sys.stderr)

    def record_failure(self, failure_reason):
        # Append a newline if there isn't one already
        if not failure_reason.endswith('\n'):
            failure_reason += '\n'
        self.failures.append(failure_reason)
        sys.stderr.write("ERROR: %s" % failure_reason)
        self.result = False

    def run(self, output):
        self.result = True
        self.failures = []
        line_num = 0
        last_packet_len = 0

        for i in range(len(output)):
            line_num += 1
            if not re.match(r"Received \d+",output[i].strip()):
                self.record_failure(f"Line {line_num} of output does not match expected, got:\n{output[i].strip()}")
                continue

            packet_len = int(output[i].split()[1])
            if packet_len <= last_packet_len:
                self.record_failure("Line {line_num} of output contains invalid packet size {packet_len} (last size: {last_packet_len})\n")
                continue

            last_packet_len = packet_len

        if (line_num == 0):
            self.record_failure("No packets seen")
        output = {'output':''.join(output)}
        if not self.result:
            output['failures'] = ''.join(self.failures)

        return self.result


def do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, test_file, seed, extra_tasks=[], rx_width=None):

    testname, extension = os.path.splitext(os.path.basename(test_file))

    if rx_width:
        profile = f'{mac}_{tx_phy.get_name()}_rx{rx_width}_{arch}'
        with capfd.disabled():
            print(f"Running {testname}: {mac} mac, {tx_phy.get_name()} phy, rx_width {rx_width}, {arch} arch sending {len(packets)} packets at {tx_clk.get_name()} (seed {seed})")
    else:
        profile = f'{mac}_{tx_phy.get_name()}_{arch}'
        with capfd.disabled():
            print(f"Running {testname}: {mac} mac, {tx_phy.get_name()} phy, {arch} arch sending {len(packets)} packets at {tx_clk.get_name()} (seed {seed})")

    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)


    tx_phy.set_packets(packets)

    tester = OutputChecker(testname, {'mac':mac, 'phy':tx_phy.get_name(), 'clk':tx_clk.get_name(), 'arch':arch})

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy, arch)

    simthreads = [tx_clk, tx_phy]
    if rx_clk:
        simthreads.append(rx_clk)
    if rx_phy:
        simthreads.append(rx_phy)

    result = px.run_on_simulator_(  binary,
                                    simthreads=simthreads + extra_tasks,
                                    tester=tester,
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    capfd=capfd
                                    )

    assert result is True, f"{result}"


def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed, rx_width=None):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()
    broadcast_mac_address = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff]

    # The inter-frame gap is to give the DUT time to print its output
    packets = []

    # Send enough basic frames to ensure the buffers in the DUT have wrapped
    for i in range(100):
        packets.append(MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (i, i+36)],
        ))

    do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed, rx_width=rx_width)


test_params_file = Path(__file__).parent / "test_rx_backpressure/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_rx_backpressure(capfd, seed, params):
    if seed == None:
        seed = random.randint(0, sys.maxsize)

    verbose = False


    # Test 100 MBit - MII XS2
    if params["phy"] == "mii":
        (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=check_received_packet, verbose=verbose)
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(verbose=verbose, test_ctrl="tile[0]:XS1_PORT_1A")
        do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    elif params["phy"] == "rmii":
        clk = get_rmii_clk(Clock.CLK_50MHz)
        tx_rmii_phy = get_rmii_tx_phy(params['rx_width'],
                                      clk,
                                      verbose=verbose,
                                      test_ctrl="tile[0]:XS1_PORT_1M"
                                      )
        do_test(capfd, params["mac"], params["arch"], None, None, clk, tx_rmii_phy, seed, rx_width=params['rx_width'])

    elif params["phy"] == "rgmii":
        # Test 100 MBit - RGMII
        if params["clk"] == "25MHz":
            (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=check_received_packet, verbose=verbose)
            (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, verbose=verbose, test_ctrl="tile[0]:XS1_PORT_1A")
            do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii, seed)
        # Test 1000 MBit - RGMII
        elif params["clk"] == "125MHz":
            (rx_clk_125, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_125MHz, packet_fn=check_received_packet, verbose=verbose)
            (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, verbose=verbose, test_ctrl="tile[0]:XS1_PORT_1A")
            do_test(capfd, params["mac"], params["arch"], rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii, seed)

        else:
            assert 0, f"Invalid params: {params}"

    else:
        assert 0, f"Invalid params: {params}"

