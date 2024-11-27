# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import Pyxsim as px
import os
import random
import sys
from pathlib import Path
import pytest

from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address, check_received_packet
from helpers import get_sim_args, create_if_needed, get_mii_tx_clk_phy, args
from helpers import get_rgmii_tx_clk_phy
from helpers import generate_tests

def do_test(capfd, mac, arch, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    testname = 'test_time_rx'

    profile = f'{mac}_{tx_phy.get_name()}_{arch}'
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    with capfd.disabled():
        print(f"Running {testname}: {mac} {tx_phy.get_name()} phy at {tx_clk.get_name()} for {arch} arch (seed {seed})")

    dut_mac_address = get_dut_mac_address()
    ifg = tx_clk.get_min_ifg()

    packets = []
    done = False
    num_data_bytes = 0
    seq_id = 0
    while not done:
        do_small_packet = rand.randint(0, 100) > 30
        if do_small_packet:
            length = rand.randint(46, 100)
        else:
            length = rand.randint(46, 1500)

        burst_len = 1
        do_burst = rand.randint(0, 100) > 80
        if do_burst:
            burst_len = rand.randint(1, 16)

        for i in range(burst_len):
            packets.append(MiiPacket(rand,
                dst_mac_addr=dut_mac_address, inter_frame_gap=ifg,
                create_data_args=['same', (seq_id, length)],
              ))
            seq_id = (seq_id + 1) & 0xff

            # Add on the overhead of the packet header
            num_data_bytes += length + 14

            if len(packets) == 150:
                done = True
                break

    tx_phy.set_packets(packets)

    with capfd.disabled():
        print(f"Sending {len(packets)} packets with {num_data_bytes} bytes at the DUT")

    expect_folder = create_if_needed("expect_temp")
    expect_filename = f'{expect_folder}/{testname}_{mac}_{tx_phy.get_name()}_{tx_clk.get_name()}_{arch}'
    create_expect(packets, expect_filename)
    tester = px.testers.ComparisonTester(open(expect_filename))

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy)

    result = px.run_on_simulator_(  binary,
                                    simthreads=[tx_clk, tx_phy],
                                    tester=tester,
                                    simargs=simargs,
                                    capfd=capfd,
                                    do_xe_prebuild=False)

    assert result is True, f"{result}"


def create_expect(packets, filename):
    """ Create the expect file for what packets should be reported by the DUT
    """
    with open(filename, 'w') as f:
        num_bytes = 0
        num_packets = 0
        for i,packet in enumerate(packets):
            if not packet.dropped:
                num_bytes += len(packet.get_packet_bytes())
                num_packets += 1
        f.write("Received {} packets, {} bytes\n".format(num_packets, num_bytes))


test_params_file = Path(__file__).parent / "test_time_rx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_time_rx(capfd, seed, params):
    verbose = False
    if seed == None:
        seed = random.randint(0, sys.maxsize)


    # Test 100 MBit - MII XS2
    if params["phy"] == "mii":
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(verbose=verbose, test_ctrl='tile[0]:XS1_PORT_1C')
        do_test(capfd, params["mac"], params["arch"], tx_clk_25, tx_mii, seed)

    elif params["phy"] == "rgmii":
        # Test 100 MBit - RGMII
        if params["clk"] == "25MHz":
            (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, verbose=verbose, test_ctrl='tile[0]:XS1_PORT_1C')
            do_test(capfd, params["mac"], params["arch"],tx_clk_25, tx_rgmii, seed)
        # Test 1000 MBit - RGMII
        elif params["clk"] == "125MHz":
            # The RGMII application cannot keep up with line-rate gigabit data
            pytest.skip()
        else:
            assert 0, f"Invalid params: {params}"

    else:
        assert 0, f"Invalid params: {params}"
