#!/usr/bin/env python
import xmostest
import os
import random
import sys
from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver

args = None

def create_if_needed(folder):
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
                       dut_exit_time=50000, initial_delay=85000):
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
                          dut_exit_time=50000, initial_delay=130000):
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

def run_on(**kwargs):
    if not args:
        return True

    for name,value in kwargs.iteritems():
        arg_value = getattr(args,name)
        if arg_value is not None and value != arg_value:
            return False

    return True

def runall_rx(test_fn):
    # Test 100 MBit - MII XS1
    (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=check_received_packet)
    (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(verbose=args.verbose)
    if run_on(phy='mii', clk='25Mhz', mac='standard', arch='xs1'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn('standard', 'xs1', rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    if run_on(phy='mii', clk='25Mhz', mac='rt', arch='xs1'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn('rt', 'xs1', rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    if run_on(phy='mii', clk='25Mhz', mac='rt_hp', arch='xs1'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn('rt_hp', 'xs1', rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    # Test 100 MBit - MII XS2
    (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=check_received_packet)
    (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(verbose=args.verbose)
    if run_on(phy='mii', clk='25Mhz', mac='standard', arch='xs2'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn('standard', 'xs2', rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    if run_on(phy='mii', clk='25Mhz', mac='rt', arch='xs2'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn('rt', 'xs2', rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    if run_on(phy='mii', clk='25Mhz', mac='rt_hp', arch='xs2'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn("rt_hp", 'xs2', rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    # Test 100 MBit - RGMII
    (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=check_received_packet)
    (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, verbose=args.verbose)
    if run_on(phy='rgmii', clk='25Mhz', mac='rt', arch='xs2'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn('rt', 'xs2', rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii, seed)

    if run_on(phy='rgmii', clk='25Mhz', mac='rt_hp', arch='xs2'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn('rt_hp', 'xs2', rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii, seed)

    # Test 1000 MBit - RGMII
    (rx_clk_125, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_125MHz, packet_fn=check_received_packet)
    (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, verbose=args.verbose)
    if run_on(phy='rgmii', clk='125Mhz', mac='rt', arch='xs2'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn('rt', 'xs2', rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii, seed)

    if run_on(phy='rgmii', clk='125Mhz', mac='rt_hp', arch='xs2'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn('rt_hp', 'xs2', rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii, seed)


def do_rx_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, test_file, seed,
               level='nightly', extra_tasks=[]):

    """ Shared test code for all RX tests using the test_rx application.
    """
    testname,extension = os.path.splitext(os.path.basename(test_file))

    resources = xmostest.request_resource("xsim")

    binary = 'test_rx/bin/{mac}_{phy}_{arch}/test_rx_{mac}_{phy}_{arch}.xe'.format(
        mac=mac, phy=tx_phy.get_name(), arch=arch)

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Running {test}: {mac} mac, {phy} phy, {arch} arch sending {n} packets at {clk} (seed {seed})".format(
            test=testname, n=len(packets), mac=mac,
            phy=tx_phy.get_name(), arch=arch, clk=tx_clk.get_name(), seed=seed)

    tx_phy.set_packets(packets)
    rx_phy.set_expected_packets(packets)

    expect_folder = create_if_needed("expect")
    expect_filename = '{folder}/{test}_{mac}_{phy}_{clk}_{arch}.expect'.format(
        folder=expect_folder, test=testname, mac=mac, phy=tx_phy.get_name(), clk=tx_clk.get_name(), arch=arch)
    create_expect(packets, expect_filename)

    tester = xmostest.ComparisonTester(open(expect_filename),
                                      'lib_ethernet', 'basic_tests', testname,
                                     {'mac':mac, 'phy':tx_phy.get_name(), 'clk':tx_clk.get_name(), 'arch':arch})

    tester.set_min_testlevel(level)

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy, arch)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[rx_clk, rx_phy, tx_clk, tx_phy] + extra_tasks,
                              tester=tester,
                              simargs=simargs)

def create_expect(packets, filename):
    """ Create the expect file for what packets should be reported by the DUT
    """
    with open(filename, 'w') as f:
        for i,packet in enumerate(packets):
            if not packet.dropped:
                f.write("Received packet {} ok\n".format(i))
        f.write("Test done\n")

def get_sim_args(testname, mac, clk, phy, arch='xs1'):
    sim_args = []

    if args and args.trace:
        log_folder = create_if_needed("logs")
        if phy.get_name() == 'rgmii':
            arch = 'xs2'
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
            print "ERROR: packet {n} does not match expected packet".format(
                n=phy.expect_packet_index)

            print "Received:"
            sys.stdout.write(packet.dump())
            print "Expected:"
            sys.stdout.write(expected.dump())

        print "Received packet {} ok".format(phy.expect_packet_index)
        # Skip this packet
        phy.expect_packet_index += 1

        # Skip on past any invalid packets
        move_to_next_valid_packet(phy)

    else:
        print "ERROR: received unexpected packet from DUT"
        print "Received:"
        sys.stdout.write(packet.dump())

    if phy.expect_packet_index >= phy.num_expected_packets:
        print "Test done"
        phy.xsi.terminate()

