# Copyright 2015-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import Pyxsim as px
import os
import random
import sys
from pathlib import Path
import json
import pytest
import subprocess

from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address, check_received_packet, args
from helpers import get_sim_args, create_if_needed, get_mii_tx_clk_phy, get_mii_rx_clk_phy
from helpers import get_rgmii_tx_clk_phy, get_rgmii_rx_clk_phy


with open(Path(__file__).parent / "test_time_rx_tx/test_params.json") as f:
    params = json.load(f)

tx_complete = False
rx_complete = False
num_test_packets = 75
test_ctrl = 'tile[0]:XS1_PORT_1C'

def start_test(phy):
    global tx_complete, rx_complete

    tx_complete = False
    rx_complete = False
    phy.num_packets = 0
    phy.num_bytes = 0
    phy.start_time = 0
    phy.end_time = 0

def set_tx_complete(phy):
    global tx_complete
    tx_complete = True

def packet_checker(packet, phy):
    global rx_complete

    time_now = phy.xsi.get_time()

    # The CRC is not included in the packet bytes
    num_packet_bytes = len(packet.get_packet_bytes()) + 4

    clock = phy.get_clock()
    bit_time = clock.get_bit_time()

    if not phy.start_time:
        packet_time = num_packet_bytes * 8 * bit_time
        phy.start_time = time_now - packet_time

    phy.num_packets += 1
    phy.num_bytes += num_packet_bytes

    time_delta = time_now - phy.start_time
    mega_bits_per_second = (phy.num_bytes * 8.0) / time_delta * 1000

    if phy.num_packets > 1:
        efficiency = ((((phy.num_bytes * 8) + ((phy.num_packets - 1) * 96)) * bit_time) / time_delta) * 100
    else:
        efficiency = (((phy.num_bytes * 8) * bit_time) / time_delta) * 100

    if phy.num_packets > num_test_packets:
        if rx_complete and tx_complete:

            # Allow time for the end of the packet to be received by the application
            # before signalling the end of the test
            phy.xsi._wait_until(phy.xsi.get_time() + 20000)

            # Indicate to the DUT receiver to print the byte count
            phy.xsi.drive_port_pins(test_ctrl, 1)
            if phy.end_time == 0:
                phy.end_time = phy.xsi.get_time()

            # Allow time for the byte count to be printed
            phy.xsi._wait_until(phy.end_time + 50000)
            phy.xsi.terminate()

    else:
        print(f"Packet {phy.num_packets} received; bytes: {num_packet_bytes}, ifg: {packet.get_ifg():.2f} => {mega_bits_per_second:.2f} Mb/s, efficiency {efficiency:.2f}%")

        if phy.num_packets == num_test_packets:
            rx_complete = True


def build_xccm(testname, config):
    result = subprocess.run('cmake -B build -G "Unix Makefiles"', shell=True, cwd=testname)
    result.check_returncode()
    result = subprocess.run(f'xmake -j 8 -C build {config}', shell=True, cwd=testname)
    result.check_returncode()
    

def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)
    start_test(rx_phy) # setup globs used in checkers

    # Generate an include file to define the seed
    with open(os.path.join("include", "seed.inc"), "w") as f:
        f.write("#define SEED {}".format(seed))

    testname = 'test_time_rx_tx'

    profile = f'{mac}_{tx_phy.get_name()}'
    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    with capfd.disabled():
        build_xccm(testname, profile)

    assert os.path.isfile(binary)

    with capfd.disabled():
        print(f"Running {testname}: {tx_phy.get_name()} phy at {tx_clk.get_name()} (seed {seed})")

    dut_mac_address = get_dut_mac_address()
    ifg = tx_clk.get_min_ifg()

    packets = []
    done = False
    num_data_bytes = 0
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
                dst_mac_addr=dut_mac_address, inter_frame_gap=ifg, num_data_bytes=length
              ))

            # Add on the overhead of the packet header
            num_data_bytes += length + 14

            if len(packets) == num_test_packets:
                done = True
                break

    tx_phy.set_packets(packets)

    with capfd.disabled():
        print(f"Sending {len(packets)} packets with {num_data_bytes} bytes at the DUT")

    expect_folder = create_if_needed("expect")
    expect_filename = '{folder}/{test}_{mac}.expect'.format(folder=expect_folder, test=testname, mac=mac)
    create_expect(packets, expect_filename)
    tester = px.testers.ComparisonTester(open(expect_filename), regexp=True)

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy)

    result = px.run_on_simulator_(  binary,
                                    simthreads=[rx_clk, rx_phy, tx_clk, tx_phy],
                                    tester=tester,
                                    simargs=simargs,
                                    capfd=capfd,
                                    do_xe_prebuild=False)

    assert result is True, f"{result}"

def create_expect(packets, filename):
    """ Create the expect file for what packets should be reported by the DUT
    """
    with open(filename, 'w') as f:
        for i in range(num_test_packets):
            f.write("Packet \\d+ received; bytes: \\d+, ifg: \\d+\\.0+ => \\d+\\.\\d+ Mb/s, efficiency \\d+\\.\\d+%\n")

        num_bytes = 0
        num_packets = 0
        for i,packet in enumerate(packets):
            if not packet.dropped:
                num_bytes += len(packet.get_packet_bytes())
                num_packets += 1
        f.write("Received {} packets, {} bytes\n".format(num_packets, num_bytes))




@pytest.mark.parametrize("params", params["PROFILES"], ids=["-".join(list(profile.values())) for profile in params["PROFILES"]])
def test_time_rx_tx(capfd, params):
    seed = 100
    verbose = False

      # Test 100 MBit - MII XS2
    if params["phy"] == "mii":
        (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=packet_checker, test_ctrl=test_ctrl)
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(do_timeout=False, complete_fn=set_tx_complete, verbose=verbose, dut_exit_time=200000 * 1e6)
        do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    elif params["phy"] == "rgmii":
        # Test 100 MBit - RGMII
        if params["clk"] == "25MHz":
            (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=packet_checker, test_ctrl=test_ctrl)
            (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, do_timeout=False, complete_fn=set_tx_complete, verbose=verbose, dut_exit_time=200000 * 1e6)
            do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii, seed)
        # Test 1000 MBit - RGMII
        elif params["clk"] == "125MHz":
            # The RGMII application cannot keep up with line-rate gigabit data
            pytest.skip()
        else:
            assert 0, f"Invalid params: {params}"

    else:
        assert 0, f"Invalid params: {params}"

