#!/usr/bin/env python

import xmostest
import os
import random
import sys
from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address, check_received_packet, packet_processing_time, args
from helpers import get_sim_args, get_mii_tx_clk_phy, get_rgmii_tx_clk_phy, run_on

def do_test(mac, tx_clk, tx_phy):
    resources = xmostest.request_resource("xsim")

    testname = 'test_link_status'

    binary = '{test}/bin/{mac}_{phy}/{test}_{mac}_{phy}.xe'.format(
        test=testname, mac=mac, phy=tx_phy.get_name())

    print "Running {test}: {phy} phy at {clk}".format(
        test=testname, phy=tx_phy.get_name(), clk=tx_clk.get_name())

    tester = xmostest.ComparisonTester(open('{}.expect'.format(testname)),
                                     'lib_ethernet', 'basic_tests', testname,
                                      {'mac':mac, 'phy':tx_phy.get_name(), 'clk':tx_clk.get_name()})

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[],
                              tester=tester,
                              simargs=simargs)

def runtest():
    # Test 100 MBit - MII
    (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(test_ctrl='tile[0]:XS1_PORT_1C',
                                             expect_loopback=False,
                                             verbose=args.verbose)
    if run_on(phy='mii', clk='25Mhz', mac='standard'):
        do_test('standard', tx_clk_25, tx_mii)
    if run_on(phy='mii', clk='25Mhz', mac='rt'):
        do_test('rt', tx_clk_25, tx_mii)

    # Test 1000 MBit - RGMII
    (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz,
                                                  verbose=args.verbose,
                                                  test_ctrl="tile[0]:XS1_PORT_1A")
    if run_on(phy='rgmii', clk='125Mhz', mac='rt'):
        do_test('rt', tx_clk_125, tx_rgmii)
