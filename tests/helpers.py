#!/usr/bin/env python
import xmostest
import os
import random
import sys
from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver

def create_if_needed(folder):
    if not os.path.exists(folder):
        os.makedirs(folder)
    return folder

def runall_rx(test_fn):
    # Test 100 MBit - MII
    rx_clk_25 = Clock('tile[0]:XS1_PORT_1I', Clock.CLK_25MHz)
    rx_mii = MiiReceiver('tile[0]:XS1_PORT_4F',
                         'tile[0]:XS1_PORT_1L',
                         rx_clk_25,
                         packet_fn=check_received_packet)

    tx_clk_25 = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_25MHz)
    tx_mii = MiiTransmitter('tile[0]:XS1_PORT_4E',
                            'tile[0]:XS1_PORT_1K',
                            tx_clk_25)

    test_fn("standard", rx_clk_25, rx_mii, tx_clk_25, tx_mii, random.randint(0, sys.maxint))
    test_fn("rt", rx_clk_25, rx_mii, tx_clk_25, tx_mii, random.randint(0, sys.maxint))

#    # Test 100 MBit - RGMII
#    clock_25 = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_25MHz)
#    rgmii = RgmiiTransmitter('tile[0]:XS1_PORT_1A',
#                         'tile[0]:XS1_PORT_4E',
#                         'tile[0]:XS1_PORT_1K',
#                         clock_25)
#
#    test_fn("rt", clock_25, rgmii)
#
#    # Test Gigabit - RGMII
#    clock_125 = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_125MHz)
#    rgmii.clock = clock_125
#
#    test_fn("rt", clock_125, rgmii)


def do_rx_test(impl, rx_clk, rx_phy, tx_clk, tx_phy, packets, test_file, seed):
    """ Shared test code for all RX tests using the test_rx application.
    """
    testname,extension = os.path.splitext(os.path.basename(test_file))

    resources = xmostest.request_resource("xsim")

    binary = 'test_rx/bin/{impl}_{phy}/test_rx_{impl}_{phy}.xe'.format(
        impl=impl, phy=tx_phy.get_name())

    print "Running {test}: {phy} phy sending {n} packets at {clk} (seed {seed})".format(
        test=testname, n=len(packets), phy=tx_phy.get_name(), clk=tx_clk.get_name(), seed=seed)

    tx_phy.set_packets(packets)
    rx_phy.set_expected_packets(packets)

    expect_folder = create_if_needed("expect")
    expect_filename = '{folder}/{test}_{impl}_{phy}_{clk}.expect'.format(
        folder=expect_folder, test=testname, impl=impl, phy=tx_phy.get_name(), clk=tx_clk.get_name())
    create_expect(packets, expect_filename)

    tester = xmostest.pass_if_matches(open(expect_filename),
                                      'lib_ethernet', 'basic_tests', testname,
                                     {'impl':impl, 'phy':tx_phy.get_name(), 'clk':tx_clk.get_name()})

    log_folder = create_if_needed("logs")
    filename = "{log}/xsim_trace_{test}_{impl}_{phy}_{clk}".format(
        log=log_folder, test=testname, impl=impl,
        clk=tx_clk.get_name(), phy=tx_phy.get_name())

    trace_args = "--trace-to {0}.txt".format(filename)
    vcd_args = ('--vcd-tracing "-o {0}.vcd -tile tile[0] '
                '-ports -ports-detailed -instructions -functions -cycles -clock-blocks"'.format(filename))

    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[rx_clk, rx_phy, tx_clk, tx_phy],
                              tester=tester,
                              simargs=[trace_args, vcd_args])

def create_expect(packets, filename):
    """ Create the expect file for what packets should be reported by the DUT
    """
    with open(filename, 'w') as f:
        for i,packet in enumerate(packets):
            if not packet.dropped:
                f.write("Received packet {} ok\n".format(i))
        f.write("Test done\n")

def packet_processing_time(data_bytes):
    """ Returns the time it takes the DUT to process a given frame
    """
    # An overhead for forwarding
    return 10000

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
            packet.dump()
            print "Expected:"
            expected.dump()

        print "Received packet {} ok".format(phy.expect_packet_index)
        # Skip this packet
        phy.expect_packet_index += 1

        # Skip on past any invalid packets
        move_to_next_valid_packet(phy)

    else:
        print "ERROR: received unexpected packet from DUT"
        print "Received:"
        packet.dump()

    if phy.expect_packet_index >= phy.num_expected_packets:
        print "Test done"
        phy.xsi.terminate()

