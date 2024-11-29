# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import os
import sys
from pathlib import Path
import pytest

import Pyxsim as px
from mii_clock import Clock
from rmii_phy import RMiiReceiver
from helpers import generate_tests
from helpers import get_sim_args

def packet_checker(packet, phy):
    print("Packet received:")
    sys.stdout.write(packet.dump(show_ifg=False))
    return

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

test_params_file = Path(__file__).parent / "test_rmii_tx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_rmii_tx(capfd, params):
    verbose = True
    test_ctrl='tile[0]:XS1_PORT_1C'

    clk = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_10MHz)
    phy = RMiiReceiver('tile[0]:XS1_PORT_4B',
                       'tile[0]:XS1_PORT_1L',
                       clk, packet_fn=packet_checker,
                      verbose=verbose, test_ctrl=test_ctrl, txd_4b_port_pin_assignment="lower_2b")

    testname = "test_rmii_tx"
    print(f"Running {testname}: {phy.get_name()} phy, at {clk.get_name()}")

    binary = f'{testname}/bin/{testname}.xe'
    assert os.path.isfile(binary)

    simargs = get_sim_args(testname, "rmii", clk, phy)
    print(f"simargs = {simargs}")

    result = px.run_on_simulator_(  binary,
                                    simthreads=[clk, phy],
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    )

