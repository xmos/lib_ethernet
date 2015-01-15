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
from helpers import get_sim_args, get_mii_tx_clk_phy

def do_test(impl, tx_clk, tx_phy):
    resources = xmostest.request_resource("xsim")

    testname = 'test_etype_filter'

    binary = '{test}/bin/{impl}_{phy}/{test}_{impl}_{phy}.xe'.format(
        test=testname, impl=impl, phy=tx_phy.get_name())

    print "Running {test}: {phy} phy at {clk}".format(
        test=testname, phy=tx_phy.get_name(), clk=tx_clk.get_name())

    dut_mac_address = get_dut_mac_address()
    packets = [
        MiiPacket(dst_mac_addr=dut_mac_address, src_mac_addr=[0 for x in range(6)],
                  ether_len_type=[0x11, 0x11], data_bytes=[1,2,3,4] + [0 for x in range(50)]),
        MiiPacket(dst_mac_addr=dut_mac_address, src_mac_addr=[0 for x in range(6)],
                  ether_len_type=[0x22, 0x22], data_bytes=[5,6,7,8] + [0 for x in range(60)])
      ]

    tx_phy.set_packets(packets)

    tester = xmostest.ComparisonTester(open('test_etype_filter.expect'),
                                     'lib_ethernet', 'basic_tests', testname,
                                      {'impl':impl, 'phy':tx_phy.get_name(), 'clk':tx_clk.get_name()})

    simargs = get_sim_args(testname, impl, tx_clk, tx_phy)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[tx_clk, tx_phy],
                              tester=tester,
                              simargs=simargs)

def runtest():
    random.seed(1)

    xmostest.build('test_etype_filter')

    # Test 100 MBit - MII
    (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(verbose=True)
    do_test("standard", tx_clk_25, tx_mii)
    do_test("rt", tx_clk_25, tx_mii)
