#!/usr/bin/env python
import xmostest
import os
import numpy.random as nprand


def do_rx_test(impl, clk, phy, packets, test_file):
    """ Shared test code for all RX tests using the test_rx application.
    """
    testname,extension = os.path.splitext(os.path.basename(test_file))
    
    resources = xmostest.request_resource("xsim")

    binary = 'test_rx/bin/{impl}_{phy}/test_rx_{impl}_{phy}.xe'.format(impl=impl, phy=phy.get_name())

    print "{phy} phy sending {n} packets at {clk}".format(n=len(packets), phy=phy.get_name(), clk=clk.get_name())
     
    phy.set_packets(packets)

    tester = xmostest.pass_if_matches(open('{0}.expect'.format(testname)),
                                     'lib_ethernet', 'basic_tests', testname,
                                     {'impl':impl, 'phy':phy.get_name(), 'clk':clk.get_name()})

    log_folder = "logs"
    if not os.path.exists(log_folder):
        os.makedirs(log_folder)
        
    filename = "{log}/xsim_trace_{test}_{impl}_{phy}_{clk}".format(
        log=log_folder, test=testname, impl=impl, clk=clk.get_name(), phy=phy.get_name())
    trace_args = "--trace-to {0}.txt".format(filename)
    vcd_args = '--vcd-tracing "-o {0}.vcd -tile tile[0] -ports -instructions -functions -cycles"'.format(filename)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads = [clk, phy],
                              tester = tester,
                              simargs = [trace_args, vcd_args])


# The time taken for the DUT to process a given frame
def packet_processing_time(data_bytes):
    # Approximate time taken to print the packet summary
    printf_time = 20000

    # Approximate time to check each data byte
    check_time = data_bytes * 125
    return printf_time + check_time
