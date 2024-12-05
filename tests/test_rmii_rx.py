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
from helpers import get_rmii_clk, get_rmii_4b_port_tx_phy, get_rmii_4b_port_rx_phy, get_rmii_1b_port_tx_phy
from helpers import check_received_packet


def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed, rx_width):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()
    broadcast_mac_address = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff]

    # The inter-frame gap is to give the DUT time to print its output
    packets = []

    for mac_address in [dut_mac_address]:
        packets.append(MiiPacket(rand,
            dst_mac_addr=mac_address,
            create_data_args=['step', (1, 46)]
          ))


    do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed, rx_width=rx_width)


test_params_file = Path(__file__).parent / "test_rmii_rx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_rx(capfd, seed, params):
    with capfd.disabled():
        print(params)

    if seed == None:
        seed = random.randint(0, sys.maxsize)
    seed = 1

    test_ctrl='tile[0]:XS1_PORT_1M'
    verbose = False

    clk = get_rmii_clk(Clock.CLK_25MHz)

    if params['rx_width'] == "4b_lower":
        tx_rmii_phy = get_rmii_4b_port_tx_phy(
                                    clk,
                                    "lower_2b",
                                    verbose=verbose,
                                    )
    elif params['rx_width'] == "4b_upper":
        tx_rmii_phy = get_rmii_4b_port_tx_phy(
                                    clk,
                                    "upper_2b",
                                    verbose=verbose,
                                    )
    elif params['rx_width'] == "1b":
        tx_rmii_phy = get_rmii_1b_port_tx_phy(
                                    clk,
                                    verbose=verbose,
                                    )
    # Hardcode rx_phy to receive on 4B lower_2b port
    rx_rmii_phy = get_rmii_4b_port_rx_phy(clk,
                                    "lower_2b",
                                    packet_fn=check_received_packet,
                                    verbose=verbose,
                                    )

    do_test(capfd, params["mac"], params["arch"], None, rx_rmii_phy, clk, tx_rmii_phy, seed, params['rx_width'])


