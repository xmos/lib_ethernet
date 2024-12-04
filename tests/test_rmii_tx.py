# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import os
import sys
from pathlib import Path
import pytest

import Pyxsim as px
from mii_clock import Clock
from helpers import generate_tests
from helpers import get_sim_args
from helpers import get_rmii_clk, get_rmii_4b_port_rx_phy, get_rmii_1b_port_rx_phy
from rmii_phy import RMiiReceiver

def packet_checker(packet, phy):
    print("Packet received:")
    sys.stdout.write(packet.dump(show_ifg=False))

    # Ignore the CRC bytes (-4)
    data = packet.data_bytes[:-4]

    if len(data) < 2:
        print(f"ERROR: packet doesn't contain enough data ({len(data)} bytes)")
        return

    step = data[1] - data[0]
    print(f"Step = {step}.")

    for i in range(len(data)-1):
        x = data[i+1] - data[i]
        x = x & 0xff;
        if x != step:
            print(f"ERROR: byte {i+1} is {x} more than byte %d (expected {step}).")
            # Only print one error per packet
            break

def do_test(capfd, mac, arch, tx_width, clk, rx_phy):
    testname = "test_rmii_tx"
    with capfd.disabled():
        print(f"Running {testname}: {mac} {rx_phy.get_name()} phy, {arch} arch {tx_width} tx_width at {clk.get_name()}")
    capfd.readouterr() # clear capfd buffer

    profile = f'{mac}_{rx_phy.get_name()}_{tx_width}_{arch}'
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    tester = px.testers.ComparisonTester(open(f'{testname}.expect'))

    simargs = get_sim_args(testname, mac, clk, rx_phy, arch=arch)
    result = px.run_on_simulator_(  binary,
                                    simthreads=[clk, rx_phy],
                                    tester=tester,
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    capfd=capfd
                                    )
    assert result is True, f"{result}"

test_params_file = Path(__file__).parent / "test_rmii_tx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_rmii_tx(capfd, params):
    verbose = True
    test_ctrl='tile[0]:XS1_PORT_1M'

    clk = get_rmii_clk(Clock.CLK_50MHz)
    if params['tx_width'] == "4b_lower":
        rx_rmii_phy = get_rmii_4b_port_rx_phy(clk,
                                    "lower_2b",
                                    packet_fn=packet_checker,
                                    verbose=verbose,
                                    test_ctrl=test_ctrl
                                    )
    elif params['tx_width'] == "4b_upper":
        rx_rmii_phy = get_rmii_4b_port_rx_phy(clk,
                            "upper_2b",
                            packet_fn=packet_checker,
                            verbose=verbose,
                            test_ctrl=test_ctrl
                            )
    elif params['tx_width'] == "1b":
        rx_rmii_phy = get_rmii_1b_port_rx_phy(clk,
                                            packet_fn=packet_checker,
                                            verbose=verbose,
                                            test_ctrl=test_ctrl)

    do_test(capfd, params["mac"], params["arch"], params['tx_width'], clk, rx_rmii_phy)

