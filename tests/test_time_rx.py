#!/usr/bin/env python

import xmostest
import os
import random
import sys
from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address, check_received_packet
from helpers import get_sim_args, create_if_needed, get_mii_tx_clk_phy, run_on, args

def do_test(impl, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    resources = xmostest.request_resource("xsim")
    testname = 'test_time_rx'
    level = 'nightly'

    binary = '{test}/bin/{impl}_{phy}/{test}_{impl}_{phy}.xe'.format(
        test=testname, impl=impl, phy=tx_phy.get_name())

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Running {test}: {phy} phy at {clk} (seed {seed})".format(
            test=testname, phy=tx_phy.get_name(), clk=tx_clk.get_name(), seed=seed)

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
            packets.append(MiiPacket(
                dst_mac_addr=dut_mac_address, inter_frame_gap=ifg, num_data_bytes=length
              ))
            
            # Add on the overhead of the packet header
            num_data_bytes += length + 14

            if len(packets) == 150:
                done = True
                break

    tx_phy.set_packets(packets)

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Sending {n} packets with {b} bytes at the DUT".format(n=len(packets), b=num_data_bytes)

    expect_folder = create_if_needed("expect")
    expect_filename = '{folder}/{test}_{impl}.expect'.format(
        folder=expect_folder, test=testname, impl=impl)
    create_expect(packets, expect_filename)
    tester = xmostest.ComparisonTester(open(expect_filename),
                                     'lib_ethernet', 'basic_tests', testname,
                                      {'impl':impl, 'phy':tx_phy.get_name(), 'clk':tx_clk.get_name()})

    tester.set_min_testlevel('nightly')

    simargs = get_sim_args(testname, impl, tx_clk, tx_phy)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[tx_clk, tx_phy],
                              tester=tester,
                              simargs=simargs)

def create_expect(packets, filename):
    """ Create the expect file for what packets should be reported by the DUT
    """
    with open(filename, 'w') as f:
        num_bytes = 0
        for i,packet in enumerate(packets):
            if not packet.dropped:
                num_bytes += len(packet.get_packet_bytes())
        f.write("Received {} bytes\n".format(num_bytes))
    
def runtest():
    if (args.seed):
        random.seed(args.seed)
    else:
        random.seed(1)

    xmostest.build('test_time_rx')

    # Test 100 MBit - MII
    (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(test_ctrl='tile[0]:XS1_PORT_1C')
    seed = random.randint(0, sys.maxint)
    if run_on(phy='mii', rate='100Mbs', mac='standard'):
        do_test("standard", tx_clk_25, tx_mii, seed)

    seed = random.randint(0, sys.maxint)
    if run_on(phy='mii', rate='100Mbs', mac='rt'):
        do_test("rt", tx_clk_25, tx_mii, seed)
