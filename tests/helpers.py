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
from rmii_phy import RMiiTransmitter, RMiiReceiver

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
                       dut_exit_time_us=(50 * px.Xsi.get_xsi_tick_freq_hz())/1e6, initial_delay_us=(85 * px.Xsi.get_xsi_tick_freq_hz())/1e6): # 50us and 85us
    clk = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_25MHz)
    phy = MiiTransmitter('tile[0]:XS1_PORT_4E',
                         'tile[0]:XS1_PORT_1K',
                         'tile[0]:XS1_PORT_1P',
                         clk,
                         verbose=verbose, test_ctrl=test_ctrl,
                         do_timeout=do_timeout, complete_fn=complete_fn,
                         expect_loopback=expect_loopback,
                         dut_exit_time_us=dut_exit_time_us, initial_delay_us=initial_delay_us)
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
                          dut_exit_time_us=(50 * px.Xsi.get_xsi_tick_freq_hz())/1e6, initial_delay_us=(130 * px.Xsi.get_xsi_tick_freq_hz())/1e6): # 50us and 135us
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
                           dut_exit_time_us=dut_exit_time_us, initial_delay_us=initial_delay_us)
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
    elif params["phy"] == "rmii":
        clk = get_rmii_clk(Clock.CLK_50MHz)
        tx_rmii_phy = get_rmii_tx_phy(params['rx_width'],
                                      clk,
                                      verbose=verbose
                                      )

        rx_rmii_phy = get_rmii_rx_phy(params['tx_width'],
                                      clk,
                                      packet_fn=check_received_packet,
                                      verbose=verbose
                                      )
        test_fn(capfd, params["mac"], params["arch"], None, rx_rmii_phy, clk, tx_rmii_phy, seed, rx_width=params['rx_width'], tx_width=params['tx_width'])
    else:
        assert 0, f"Invalid params: {params}"


def do_rx_test(capfd, mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, test_file, seed,
               extra_tasks=[], override_dut_dir=False, rx_width=None, tx_width=None):

    """ Shared test code for all RX tests using the test_rx application.
    """
    testname,extension = os.path.splitext(os.path.basename(test_file))

    with capfd.disabled():
        print(f"Running {testname}: {mac} {tx_phy.get_name()} phy, {arch}, rx_width {rx_width} arch at {tx_clk.get_name()} (seed = {seed})")
    capfd.readouterr() # clear capfd buffer

    profile = f'{mac}_{tx_phy.get_name()}'
    if rx_width:
        profile = profile + f"_rx{rx_width}"
    if tx_width:
        profile = profile + f"_tx{tx_width}"
    profile = profile + f"_{arch}"

    dut_dir = override_dut_dir if override_dut_dir else testname
    binary = f'{dut_dir}/bin/{profile}/{dut_dir}_{profile}.xe'
    assert os.path.isfile(binary), f"Missing .xe {binary}"

    tx_phy.set_packets(packets)
    rx_phy.set_expected_packets(packets)

    expect_folder = create_if_needed("expect_temp")
    if rx_width:
        expect_filename = f'{expect_folder}/{testname}_{mac}_{tx_phy.get_name()}_{rx_width}_{tx_width}_{tx_clk.get_name()}_{arch}.expect'
    else:
        expect_filename = f'{expect_folder}/{testname}_{mac}_{tx_phy.get_name()}_{tx_clk.get_name()}_{arch}.expect'

    create_expect(packets, expect_filename)

    tester = px.testers.ComparisonTester(open(expect_filename))

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy, arch)
    # with capfd.disabled():
    #     print(f"simargs {simargs}\n bin: {binary}")
    if rx_clk == None: # RMII has only one clock
        st = [tx_clk, rx_phy, tx_phy]
    else:
        st = [rx_clk, rx_phy, tx_clk, tx_phy]

    result = px.run_on_simulator_(  binary,
                                    simthreads=st + extra_tasks,
                                    tester=tester,
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    capfd=capfd
                                    )

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
                     ' -functions -cycles -clock-blocks -pads')

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
    # TODO Investigate why this function ignores the data_bytes argument and
    # returns a fixed number for a given mac type
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
                test_profile_id = copy.deepcopy(test_profile)
                # For id, append tx and rx to the relevant widths so its easier to know which is which if both are present
                if 'tx_width' in test_profile_id:
                    test_profile_id['tx_width'] = f"tx{test_profile_id['tx_width']}"
                if 'rx_width' in test_profile_id:
                    test_profile_id['rx_width'] = f"rx{test_profile_id['rx_width']}"
                id = '-'.join([v for v in test_profile_id.values()])
                test_config_ids.append(id)
                test_config_list.append(test_profile)

    return test_config_list, test_config_ids

### RMII functions
def get_rmii_clk(clk_rate):
    clk = Clock('tile[0]:XS1_PORT_1J', clk_rate)
    return clk

def get_rmii_tx_phy(rx_width, clk, **kwargs):
    if rx_width == "4b_lower":
        tx_rmii_phy = get_rmii_4b_port_tx_phy(
                                    clk,
                                    "lower_2b",
                                    **kwargs
                                    )
    elif rx_width == "4b_upper":
        tx_rmii_phy = get_rmii_4b_port_tx_phy(
                                    clk,
                                    "upper_2b",
                                    **kwargs
                                    )
    elif rx_width == "1b":
        tx_rmii_phy = get_rmii_1b_port_tx_phy(
                                    clk,
                                    **kwargs
                                    )
    else:
        assert False, f"get_rmii_tx_phy(): Invalid rx_width {rx_width}"
    return tx_rmii_phy

def get_rmii_rx_phy(tx_width, clk, **kwargs):
    if tx_width == "4b_lower":
        rx_rmii_phy = get_rmii_4b_port_rx_phy(clk,
                                              "lower_2b",
                                              **kwargs
                                              )
    elif tx_width == "4b_upper":
        rx_rmii_phy = get_rmii_4b_port_rx_phy(clk,
                                              "upper_2b",
                                              **kwargs
                                              )
    elif tx_width == "1b":
        rx_rmii_phy = get_rmii_1b_port_rx_phy(clk,
                                              **kwargs
                                            )
    else:
        assert False, f"get_rmii_rx_phy(): Invalid tx_width {tx_width}"
    return rx_rmii_phy



def get_rmii_4b_port_tx_phy(clk, rxd_4b_port_pin_assignment, **kwargs):
    rxd = 'tile[0]:XS1_PORT_4C' if "second_phy" in kwargs else 'tile[0]:XS1_PORT_4A'
    rxdv = 'tile[0]:XS1_PORT_1O' if "second_phy" in kwargs else 'tile[0]:XS1_PORT_1K'
    rxderr = 'tile[0]:XS1_PORT_1I' # Currently unused so assign the same
    if "second_phy" in kwargs: kwargs.pop("second_phy")

    phy = RMiiTransmitter(rxd, # 4b rxd port
                          rxdv, # 1b rxdv
                          rxderr, # 1b rxerr
                          clk,
                          rxd_4b_port_pin_assignment=rxd_4b_port_pin_assignment,
                          **kwargs
                        )
    return phy

def get_rmii_1b_port_tx_phy(clk, **kwargs):
    rxd = ['tile[0]:XS1_PORT_1E', 'tile[0]:XS1_PORT_1F'] if "second_phy" in kwargs else ['tile[0]:XS1_PORT_1A', 'tile[0]:XS1_PORT_1B']
    rxdv = 'tile[0]:XS1_PORT_1O' if "second_phy" in kwargs else 'tile[0]:XS1_PORT_1K'
    rxderr = 'tile[0]:XS1_PORT_1I' # Currently unused so assign the same
    if "second_phy" in kwargs: kwargs.pop("second_phy")

    phy = RMiiTransmitter(rxd, # 2, 1b rxd ports
                          rxdv, # 1b rxdv
                          rxderr, # 1b rxerr
                          clk,
                          **kwargs
                        )
    return phy

def get_rmii_4b_port_rx_phy(clk, txd_4b_port_pin_assignment, **kwargs):
    txd = 'tile[0]:XS1_PORT_4D' if "second_phy" in kwargs else 'tile[0]:XS1_PORT_4B'
    txen = 'tile[0]:XS1_PORT_1P' if "second_phy" in kwargs else 'tile[0]:XS1_PORT_1L'
    if "second_phy" in kwargs: kwargs.pop("second_phy")

    phy = RMiiReceiver(txd,
                       txen,
                       clk,
                       txd_4b_port_pin_assignment=txd_4b_port_pin_assignment,
                       **kwargs
                       )
    return phy

def get_rmii_1b_port_rx_phy(clk, **kwargs):
    txd = ['tile[0]:XS1_PORT_1H', 'tile[0]:XS1_PORT_1I'] if "second_phy" in kwargs else ['tile[0]:XS1_PORT_1C', 'tile[0]:XS1_PORT_1D']
    txen = 'tile[0]:XS1_PORT_1P' if "second_phy" in kwargs else 'tile[0]:XS1_PORT_1L'
    if "second_phy" in kwargs: kwargs.pop("second_phy")

    phy = RMiiReceiver(txd,
                       txen,
                       clk,
                       **kwargs
                       )
    return phy

