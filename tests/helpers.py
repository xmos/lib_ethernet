# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import os
import random
import sys
from types import SimpleNamespace
import Pyxsim as px
from filelock import FileLock
import pytest
import json
import copy

from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver

args = SimpleNamespace( trace=False, # Set to True to enable VCD and instruction tracing for debug. Warning - it's about 5x slower with trace on and creates up to ~1GB of log files in tests/logs
                        num_packets=100, # Number of packets in the test
                        weight_hp=50, # Weight of high priority traffic
                        weight_lp=25, # Weight of low priority traffic
                        weight_other=25, # Weight of other (dropped) traffic
                        data_len_min=46, # Minimum packet data bytes
                        data_len_max=500, # Maximum packet data bytes
                        weight_tagged=50, # Weight of VLAN tagged traffic'
                        weight_untagged=50, # Weight of non-VLAN tagged traffic
                        max_hp_mbps=1000, # The maximum megabits per second
                        )

def create_if_needed(folder):
    lock_path = f"{folder}.lock"
    # xdist can cause race conditions so use a lock
    with FileLock(lock_path):
        if not os.path.exists(folder):
            os.makedirs(folder)
        return folder

# A set of functions to create the clock and phy for tests. This set of functions
# contains all the port mappings for the different phys.
def get_mii_rx_clk_phy(packet_fn=None, verbose=False, test_ctrl=None):
    clk = Clock('tile[0]:XS1_PORT_1I', Clock.CLK_25MHz)
    phy = MiiReceiver('tile[0]:XS1_PORT_4F',
                      'tile[0]:XS1_PORT_1L',
                      clk, packet_fn=packet_fn,
                      verbose=verbose, test_ctrl=test_ctrl)
    return (clk, phy)

def get_mii_tx_clk_phy(verbose=False, test_ctrl=None, do_timeout=True,
                       complete_fn=None, expect_loopback=True,
                       dut_exit_time=50000*1e6, initial_delay=85000*1e6):
    clk = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_25MHz)
    phy = MiiTransmitter('tile[0]:XS1_PORT_4E',
                         'tile[0]:XS1_PORT_1K',
                         'tile[0]:XS1_PORT_1P',
                         clk,
                         verbose=verbose, test_ctrl=test_ctrl,
                         do_timeout=do_timeout, complete_fn=complete_fn,
                         expect_loopback=expect_loopback,
                         dut_exit_time=dut_exit_time, initial_delay=initial_delay)
    return (clk, phy)

def get_rgmii_rx_clk_phy(clk_rate, packet_fn=None, verbose=False, test_ctrl=None):
    clk = Clock('tile[1]:XS1_PORT_1P', clk_rate)
    phy = RgmiiReceiver('tile[1]:XS1_PORT_8B',
                        'tile[1]:XS1_PORT_1F',
                        clk, packet_fn=packet_fn,
                        verbose=verbose, test_ctrl=test_ctrl)
    return (clk, phy)

def get_rgmii_tx_clk_phy(clk_rate, verbose=False, test_ctrl=None,
                          do_timeout=True, complete_fn=None, expect_loopback=True,
                          dut_exit_time=50000*1e6, initial_delay=130000*1e6):
    clk = Clock('tile[1]:XS1_PORT_1O', clk_rate)
    phy = RgmiiTransmitter('tile[1]:XS1_PORT_8A',
                           'tile[1]:XS1_PORT_4E',
                           'tile[1]:XS1_PORT_1B',
                           'tile[1]:XS1_PORT_4F',
                           'tile[1]:XS1_PORT_1K',
                           'tile[1]:XS1_PORT_1A',
                           clk,
                           verbose=verbose, test_ctrl=test_ctrl,
                           do_timeout=do_timeout, complete_fn=complete_fn,
                           expect_loopback=expect_loopback,
                           dut_exit_time=dut_exit_time, initial_delay=initial_delay)
    return (clk, phy)


def run_parametrised_test_rx(capfd, test_fn, params, exclude_standard=False, verbose=False, seed=False):
    seed = seed if seed else random.randint(0, sys.maxsize)

    # Test 100 MBit - MII XS2
    if params["phy"] == "mii":
        if exclude_standard and params["mac"] == "standard":
            pytest.skip()
        (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=check_received_packet)
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(verbose=verbose)
        test_fn(capfd, params["mac"], params["arch"], rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    elif params["phy"] == "rgmii":
        # Test 100 MBit - RGMII
        if params["clk"] == "25MHz":
            (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=check_received_packet)
            (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, verbose=verbose)
            test_fn(capfd, params["mac"], params["arch"], rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii, seed)
        # Test 1000 MBit - RGMII
        elif params["clk"] == "125MHz":
            (rx_clk_125, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_125MHz, packet_fn=check_received_packet)
            (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, verbose=verbose)
            test_fn(capfd, params["mac"], params["arch"], rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii, seed)

        else:
            assert 0, f"Invalid params: {params}"

    else:
        assert 0, f"Invalid params: {params}"


def do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, test_file, seed,
               extra_tasks=[], override_dut_dir=False):

    """ Shared test code for all RX tests using the test_rx application.
    """
    testname,extension = os.path.splitext(os.path.basename(test_file))

    with capfd.disabled():
        print(f"Running {testname}: {mac} {tx_phy.get_name()} phy, {arch} arch at {tx_clk.get_name()} (seed = {seed})")
    capfd.readouterr() # clear capfd buffer

    profile = f'{mac}_{tx_phy.get_name()}_{arch}'
    dut_dir = override_dut_dir if override_dut_dir else testname
    binary = f'{dut_dir}/bin/{profile}/{dut_dir}_{profile}.xe'
    assert os.path.isfile(binary), f"Missing .xe {binary}"

    tx_phy.set_packets(packets)
    rx_phy.set_expected_packets(packets)

    expect_folder = create_if_needed("expect_temp")
    expect_filename = f'{expect_folder}/{testname}_{mac}_{tx_phy.get_name()}_{tx_clk.get_name()}_{arch}.expect'

    create_expect(packets, expect_filename)

    tester = px.testers.ComparisonTester(open(expect_filename))

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy, arch)
    # with capfd.disabled():
    #     print(f"simargs {simargs}\n bin: {binary}")
    result = px.run_on_simulator_(  binary,
                                    simthreads=[rx_clk, rx_phy, tx_clk, tx_phy] + extra_tasks,
                                    tester=tester,
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    capfd=capfd)

    assert result is True, f"{result}"


def create_expect(packets, filename):
    """ Create the expect file for what packets should be reported by the DUT
    """
    with open(filename, 'w') as f:
        for i,packet in enumerate(packets):
            if not packet.dropped:
                f.write("Received packet {} ok\n".format(i))
        f.write("Test done\n")

def get_sim_args(testname, mac, clk, phy, arch='xs2'):
    sim_args = []

    if args and args.trace:
        log_folder = create_if_needed("logs")

        filename = "{log}/xsim_trace_{test}_{mac}_{phy}_{clk}_{arch}".format(
            log=log_folder, test=testname, mac=mac,
            clk=clk.get_name(), phy=phy.get_name(), arch=arch)

        sim_args += ['--trace-to', '{0}.txt'.format(filename), '--enable-fnop-tracing']

        vcd_args  = '-o {0}.vcd'.format(filename)
        vcd_args += (' -tile tile[0] -ports -ports-detailed -instructions'
                     ' -functions -cycles -clock-blocks')

        # The RGMII pins are on tile[1]
        if phy.get_name() == 'rgmii':
                vcd_args += (' -tile tile[1] -ports -ports-detailed -instructions'
                             ' -functions -cycles -clock-blocks')

        sim_args += ['--vcd-tracing', vcd_args]

#        sim_args += ['--xscope', '-offline logs/xscope.xmt']

    return sim_args

def packet_processing_time(phy, data_bytes, mac):
    """ Returns the time it takes the DUT to process a given frame
    """
    if mac == 'standard':
        return 4000 * phy.get_clock().get_bit_time()
    elif phy.get_name() == 'rgmii' and mac == 'rt':
        return 6000 * phy.get_clock().get_bit_time()
    else:
        return 2000 * phy.get_clock().get_bit_time()

def get_dut_mac_address():
    """ Returns the MAC address of the DUT
    """
    return [0,1,2,3,4,5]

def choose_small_frame_size(rand):
    """ Choose the size of a frame near the minimum size frame (46 data bytes)
    """
    return rand.randint(46, 54)

def move_to_next_valid_packet(phy):
    while (phy.expect_packet_index < phy.num_expected_packets and
           phy.expected_packets[phy.expect_packet_index].dropped):
        phy.expect_packet_index += 1

def check_received_packet(packet, phy):
    if phy.expected_packets is None:
        return

    move_to_next_valid_packet(phy)

    if phy.expect_packet_index < phy.num_expected_packets:
        expected = phy.expected_packets[phy.expect_packet_index]
        if packet != expected:
            print(f"ERROR: packet {phy.expect_packet_index} does not match expected packet {expected}")

            print(f"Received:")
            sys.stdout.write(packet.dump())
            print("Expected:")
            sys.stdout.write(expected.dump())

        print(f"Received packet {phy.expect_packet_index} ok")
        # Skip this packet
        phy.expect_packet_index += 1

        # Skip on past any invalid packets
        move_to_next_valid_packet(phy)

    else:
        print(f"ERROR: received unexpected packet from DUT")
        print("Received:")
        sys.stdout.write(packet.dump())

    if phy.expect_packet_index >= phy.num_expected_packets:
        print("Test done")
        phy.xsi.terminate()

def generate_tests(test_params_json):
    with open(test_params_json) as f:
        params = json.load(f)
        test_config_list = []
        test_config_ids = []
        for profile in params['PROFILES']:
            base_profile = {key: value for key,value in profile.items() if key != 'arch'} # copy everything but 'arch'
            if isinstance(profile['arch'], str):
                profile['arch'] = [profile['arch']]
            for a in profile['arch']: # Add a test case per architecture
                test_profile = copy.deepcopy(base_profile)
                test_profile['arch'] = a
                id = '-'.join([v for v in test_profile.values()])
                test_config_ids.append(id)
                test_config_list.append(test_profile)
    return test_config_list, test_config_ids
