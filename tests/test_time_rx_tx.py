# Copyright 2015-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import Pyxsim as px
import os
import random
import sys
from pathlib import Path
import pytest
import subprocess
from filelock import FileLock
import re

from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address, check_received_packet, args
from helpers import get_sim_args, create_if_needed, get_mii_tx_clk_phy, get_mii_rx_clk_phy
from helpers import get_rgmii_tx_clk_phy, get_rgmii_rx_clk_phy
from helpers import get_rmii_clk, get_rmii_4b_port_tx_phy, get_rmii_1b_port_tx_phy, get_rmii_4b_port_rx_phy, get_rmii_1b_port_rx_phy
from helpers import generate_tests

tx_complete = False
rx_complete = False
num_test_packets = 75

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

def packet_checker(packet, phy, test_ctrl):
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
    mega_bits_per_second = ((phy.num_bytes * 8.0) * px.Xsi.get_xsi_tick_freq_hz()) / (time_delta * 1e6)

    if phy.num_packets > 1:
        efficiency = ((((phy.num_bytes * 8) + ((phy.num_packets - 1) * 96)) * bit_time) / time_delta) * 100
    else:
        efficiency = (((phy.num_bytes * 8) * bit_time) / time_delta) * 100

    if phy.num_packets > num_test_packets:
        if rx_complete and tx_complete:

            # Allow time for the end of the packet to be received by the application
            # before signalling the end of the test
            phy.xsi._wait_until(phy.xsi.get_time() + 20000 * 1e6)

            # Indicate to the DUT receiver to print the byte count
            if test_ctrl:
                phy.xsi.drive_port_pins(test_ctrl, 1)
            if phy.end_time == 0:
                phy.end_time = phy.xsi.get_time()

            # Allow time for the byte count to be printed
            phy.xsi._wait_until(phy.end_time + 50000 * 1e6)
            phy.xsi.terminate()

    else:
        print(f"Packet {phy.num_packets} received; bytes: {num_packet_bytes}, ifg: {packet.get_ifg():.2f} => {mega_bits_per_second:.2f} Mb/s, efficiency {efficiency:.2f}%")

        if phy.num_packets == num_test_packets:
            rx_complete = True


def build_xccm(testname, config):
    lock_path = f"{testname}.lock"
    # xdist can cause race conditions so use a lock
    with FileLock(lock_path):
        result = subprocess.run('cmake -B build -G "Unix Makefiles"', shell=True, cwd=testname)
        result.check_returncode()
        result = subprocess.run(f'xmake -j 8 -C build {config}', shell=True, cwd=testname)
        result.check_returncode()


# I had problems with the comparison tester putting a newline in the expected regex so wrote custom one and replaced create_expect
class mytester:
    def __init__(self, packets):
        num_bytes = 0
        num_packets = 0
        for i,packet in enumerate(packets):
            if not packet.dropped:
                num_bytes += len(packet.get_packet_bytes())
                num_packets += 1

        self.num_packets = num_packets
        self.num_bytes = num_bytes

    def run(self, output):
        result = True

        expected_summary = f"Received {self.num_packets} packets, {self.num_bytes} bytes"
        found_summary = False
        for line in output:
            match = re.match(expected_summary, line.strip())
            if match:
                found_summary = True
                output.remove(line)

        if not found_summary:
            sys.stderr.write(f"Expected to find:\n `{expected_summary}`\n in:\n `{output}`\n")
            return False


        exected_other_lines = r"Packet \d+ received; bytes: \d+, ifg: \d+.0+ => \d+.\d+ Mb/s, efficiency \d+.\d+%"
        if self.num_packets > len(output) + 1:
            sys.stderr.write(f"Unexpectedly short output:\n `{output[1:]}`\n")
            return False
        for line_num in range(self.num_packets):
            match = re.match(exected_other_lines, output[line_num].strip())
            if not match:
                result = False
                sys.stderr.write(f"Line {line_num} expected:\n `{exected_other_lines}`\n got:\n `{output[line_num].strip()}`\n")

        return result



def do_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed, rx_width=None, tx_width=None):
    rand = random.Random()
    rand.seed(seed)
    start_test(rx_phy) # setup globs used in checkers

    # Generate an include file to define the seed
    with open(os.path.join("include", "seed.inc"), "w") as f:
        f.write("#define SEED {}".format(seed))

    testname = 'test_time_rx_tx'

    if rx_width and tx_width:
        profile = f'{mac}_{tx_phy.get_name()}_rx{rx_width}_tx{tx_width}_{arch}'
        with capfd.disabled():
            print(f"Running {testname}: {tx_phy.get_name()} phy {rx_width} rx_width, {tx_width} tx_width, at {tx_clk.get_name()} (seed {seed}) for {arch} arch")
    else:
        profile = f'{mac}_{tx_phy.get_name()}_{arch}'
        with capfd.disabled():
            print(f"Running {testname}: {tx_phy.get_name()} phy at {tx_clk.get_name()} (seed {seed}) for {arch} arch")

    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    with capfd.disabled():
        build_xccm(testname, profile)

    assert os.path.isfile(binary)

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
                dst_mac_addr=dut_mac_address,
                inter_frame_gap=ifg,
                num_data_bytes=length
              ))

            # Add on the overhead of the packet header
            num_data_bytes += length + 14

            if len(packets) == num_test_packets:
                done = True
                break

    tx_phy.set_packets(packets)

    with capfd.disabled():
        print(f"Sending {len(packets)} packets with {num_data_bytes} bytes at the DUT")

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy)
    if rx_clk:
        simthreads=[rx_clk, rx_phy, tx_clk, tx_phy]
    else:
        simthreads=[rx_phy, tx_clk, tx_phy]

    result = px.run_on_simulator_(  binary,
                                    simthreads=simthreads,
                                    tester=mytester(packets),
                                    simargs=simargs,
                                    capfd=capfd,
                                    do_xe_prebuild=False)

    assert result is True, f"{result}"


test_params_file = Path(__file__).parent / "test_time_rx_tx/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_time_rx_tx(capfd, seed, params):
    if seed == None:
        seed = random.randint(0, sys.maxsize)

    verbose = False

      # Test 100 MBit - MII XS2
    if params["phy"] == "mii":
        test_ctrl = 'tile[0]:XS1_PORT_1C'
        (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=packet_checker, test_ctrl=test_ctrl)
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(do_timeout=False, complete_fn=set_tx_complete, verbose=verbose, dut_exit_time=(200 * px.Xsi.get_xsi_tick_freq_hz())/1e6)
        do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    elif params["phy"] == "rgmii":
        # Test 100 MBit - RGMII
        test_ctrl = 'tile[0]:XS1_PORT_1C'
        if params["clk"] == "25MHz":
            (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=packet_checker, test_ctrl=test_ctrl)
            (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, do_timeout=False, complete_fn=set_tx_complete, verbose=verbose, dut_exit_time=(200 * px.Xsi.get_xsi_tick_freq_hz())/1e6)
            do_test(capfd, params["mac"], params["arch"], rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii, seed)
        # Test 1000 MBit - RGMII
        elif params["clk"] == "125MHz":
            # The RGMII application cannot keep up with line-rate gigabit data
            pytest.skip()
        else:
            assert 0, f"Invalid params: {params}"
    elif params["phy"] == "rmii":
        test_ctrl = 'tile[0]:XS1_PORT_1M'
        rmii_clk = get_rmii_clk(Clock.CLK_50MHz)
        if params['rx_width'] == "4b_lower":
            tx_rmii_phy = get_rmii_4b_port_tx_phy(
                                        rmii_clk,
                                        "lower_2b",
                                        do_timeout=False,
                                        complete_fn=set_tx_complete,
                                        verbose=verbose,
                                        dut_exit_time=(200 * px.Xsi.get_xsi_tick_freq_hz())/1e6
                                        )
        elif params['rx_width'] == "4b_upper":
            tx_rmii_phy = get_rmii_4b_port_tx_phy(
                                        rmii_clk,
                                        "upper_2b",
                                        do_timeout=False,
                                        complete_fn=set_tx_complete,
                                        verbose=verbose,
                                        dut_exit_time=(200 * px.Xsi.get_xsi_tick_freq_hz())/1e6
                                        )
        elif params['rx_width'] == "1b":
            tx_rmii_phy = get_rmii_1b_port_tx_phy(
                                        rmii_clk,
                                        do_timeout=False,
                                        complete_fn=set_tx_complete,
                                        verbose=verbose,
                                        dut_exit_time=(200 * px.Xsi.get_xsi_tick_freq_hz())/1e6
                                        )

        if params['tx_width'] == "4b_lower":
            rx_rmii_phy = get_rmii_4b_port_rx_phy(rmii_clk,
                                            "lower_2b",
                                            packet_fn=packet_checker,
                                            test_ctrl=test_ctrl,
                                            )
        elif params['tx_width'] == "4b_upper":
            rx_rmii_phy = get_rmii_4b_port_rx_phy(rmii_clk,
                                            "upper_2b",
                                            packet_fn=packet_checker,
                                            test_ctrl=test_ctrl,
                                            )
        elif params['tx_width'] == "1b":
            rx_rmii_phy = get_rmii_1b_port_rx_phy(rmii_clk,
                                            packet_fn=packet_checker,
                                            test_ctrl=test_ctrl,
                                            )
        do_test(capfd, params["mac"], params["arch"], None, rx_rmii_phy, rmii_clk, tx_rmii_phy, seed,
                rx_width=params["rx_width"], tx_width=params["tx_width"])
    else:
        assert 0, f"Invalid params: {params}"

