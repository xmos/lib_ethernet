#!/usr/bin/env python
import xmostest
import os
from mii_clock import Clock
from mii_phy import MiiReceiver
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import get_sim_args, create_if_needed, run_on, args
from helpers import get_mii_rx_clk_phy, get_mii_tx_clk_phy, get_rgmii_rx_clk_phy, get_rgmii_tx_clk_phy

num_test_packets = 150

def start_test(phy):
    phy.num_packets = 0
    phy.num_bytes = 0
    phy.start_time = 0

def packet_checker(packet, phy):
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

    print "Packet {} received; bytes: {}, ifg: {} => {:.2f} Mb/s, efficiency {:.2f}%".format(
        phy.num_packets, num_packet_bytes, packet.get_ifg(), mega_bits_per_second, efficiency)

    if phy.num_packets == num_test_packets:
        phy.xsi.terminate()

def do_test(mac, rx_clk, rx_phy, tx_clk, tx_phy):
    start_test(rx_phy)

    resources = xmostest.request_resource("xsim")

    testname = 'test_time_tx'
    level = 'nightly'

    binary = '{test}/bin/{mac}_{phy}/{test}_{mac}_{phy}.xe'.format(
        test=testname, mac=mac, phy=rx_phy.get_name())

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Running {test}: {mac} {phy} phy at {clk}".format(
            test=testname, mac=mac, phy=rx_phy.get_name(), clk=rx_clk.get_name())

    expect_folder = create_if_needed("expect")
    expect_filename = '{folder}/{test}_{mac}_{phy}_{clk}.expect'.format(
        folder=expect_folder, test=testname, mac=mac, phy=rx_phy.get_name(), clk=rx_clk.get_name())
    create_expect(expect_filename)

    tester = xmostest.ComparisonTester(open(expect_filename),
                                     'lib_ethernet', 'basic_tests', testname,
                                     {'mac':mac, 'phy':rx_phy.get_name(), 'clk':rx_clk.get_name()},
                                     regexp=True)

    tester.set_min_testlevel('nightly')

    simargs = get_sim_args(testname, mac, rx_clk, rx_phy)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[rx_clk, rx_phy, tx_clk, tx_phy],
                              tester=tester,
                              simargs=simargs)

def create_expect(filename):
    """ Create the expect file for what packets should be reported by the DUT
    """
    with open(filename, 'w') as f:
        for i in range(num_test_packets):
            f.write("Packet \\d+ received; bytes: \\d+, ifg: \\d+\\.0 => \\d+\\.\\d+ Mb/s, efficiency \\d+\\.\\d+%\n")

def runtest():
    # Test 100 MBit - MII
    (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=packet_checker)
    (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(do_timeout=False, verbose=args.verbose)
    if run_on(phy='mii', clk='25Mhz', mac='standard'):
        do_test('standard', rx_clk_25, rx_mii, tx_clk_25, tx_mii)
    if run_on(phy='mii', clk='25Mhz', mac='rt'):
        do_test('rt', rx_clk_25, rx_mii, tx_clk_25, tx_mii)
    if run_on(phy='mii', clk='25Mhz', mac='rt_hp'):
        do_test('rt_hp', rx_clk_25, rx_mii, tx_clk_25, tx_mii)

    # Test 100 MBit - RGMII
    (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=packet_checker)
    (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, do_timeout=False,
                                                 verbose=args.verbose)
    if run_on(phy='rgmii', clk='25Mhz', mac='rt'):
        do_test('rt', rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii)
    if run_on(phy='rgmii', clk='25Mhz', mac='rt_hp'):
        do_test('rt_hp', rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii)

    # Test 1000 MBit - RGMII
    (rx_clk_125, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_125MHz, packet_fn=packet_checker)
    (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, do_timeout=False,
                                                  verbose=args.verbose)
    if run_on(phy='rgmii', clk='125Mhz', mac='rt'):
        do_test('rt', rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii)
    if run_on(phy='rgmii', clk='125Mhz', mac='rt_hp'):
        do_test('rt_hp', rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii)

