import random
import Pyxsim as px
from pathlib import Path
import pytest
import sys
import os

from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, run_parametrised_test_rx
from helpers import generate_tests
from mii_clock import Clock
from rmii_phy import RMiiTransmitter
from helpers import get_sim_args

test_params_file = Path(__file__).parent / "test_rmii_tx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_rmii_rx(params):
    verbose = True
    test_ctrl='tile[0]:XS1_PORT_1C'

    clk = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_10MHz)
    phy = RMiiTransmitter('tile[0]:XS1_PORT_4A',
                          'tile[0]:XS1_PORT_1K',
                          'tile[0]:XS1_PORT_1I',
                          clk,
                          verbose=verbose,
                          rxd_4b_port_pin_assignment="lower_2b"
                          )

    testname = "test_rmii_rx"
    print(f"Running {testname}: {phy.get_name()} phy, at {clk.get_name()}")

    binary = f'{testname}/bin/{testname}.xe'
    assert os.path.isfile(binary)

    seed = 0
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()
    broadcast_mac_address = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff]
    packets = []
    for mac_address in [dut_mac_address]:
        packets.append(MiiPacket(rand,
            dst_mac_addr=mac_address,
            create_data_args=['step', (1, 87)]
          ))

    phy.set_packets(packets)

    simargs = get_sim_args(testname, "rmii", clk, phy)
    print(f"simargs = {simargs}")

    result = px.run_on_simulator_(  binary,
                                    simthreads=[clk, phy],
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    )

