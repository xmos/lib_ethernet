#!/usr/bin/env python
import xmostest
import os
import random

def create_if_needed(folder):
    if not os.path.exists(folder):
        os.makedirs(folder)
    return folder

def do_rx_test(impl, clk, phy, packets, test_file, seed):
    """ Shared test code for all RX tests using the test_rx application.
    """
    testname,extension = os.path.splitext(os.path.basename(test_file))

    resources = xmostest.request_resource("xsim")

    binary = 'test_rx/bin/{impl}_{phy}/test_rx_{impl}_{phy}.xe'.format(
        impl=impl, phy=phy.get_name())

    print "Running {test}: {phy} phy sending {n} packets at {clk} (seed {seed})".format(
        test=testname, n=len(packets), phy=phy.get_name(), clk=clk.get_name(), seed=seed)

    phy.set_packets(packets)

    expect_folder = create_if_needed("expect")
    expect_filename = '{folder}/{test}_{impl}_{phy}_{clk}.expect'.format(
        folder=expect_folder, test=testname, impl=impl, phy=phy.get_name(), clk=clk.get_name())
    create_expect(packets, expect_filename)

    tester = xmostest.pass_if_matches(open(expect_filename),
                                      'lib_ethernet', 'basic_tests', testname,
                                     {'impl':impl, 'phy':phy.get_name(), 'clk':clk.get_name()})

    log_folder = create_if_needed("logs")
    filename = "{log}/xsim_trace_{test}_{impl}_{phy}_{clk}".format(
        log=log_folder, test=testname, impl=impl,
        clk=clk.get_name(), phy=phy.get_name())

    trace_args = "--trace-to {0}.txt".format(filename)
    vcd_args = ('--vcd-tracing "-o {0}.vcd -tile tile[0] '
                '-ports -instructions -functions -cycles"'.format(filename))

    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[clk, phy],
                              tester=tester,
                              simargs=[trace_args, vcd_args])

def create_expect(packets, filename):
    """ Create the expect file for what packets should be reported by the DUT
    """
    with open(filename, 'w') as f:
        for packet in packets:
            if packet.dropped:
                continue

            # The packet type is always 0 to indicate it is a data packet
            f.write('Received packet, type=0, len={l}.\n'.format(
                l=len(packet.get_packet_bytes())))
            f.write(packet.get_data_expect())

def packet_processing_time(data_bytes):
    """ Returns the time it takes the DUT to process a given frame
    """

    # Approximate time taken to print the packet summary
    printf_time = 20000

    # Approximate time to check each data byte
    check_time = data_bytes * 125
    return printf_time + check_time

def get_dut_mac_address():
    """ Returns the MAC address of the DUT
    """
    return [0,1,2,3,4,5]

def choose_small_frame_size(rand):
    """ Choose the size of a frame near the minimum size frame (46 data bytes)
    """
    return rand.randint(46, 54)
