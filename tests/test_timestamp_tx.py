#!/usr/bin/env python
import xmostest
import os
import sys
from mii_clock import Clock
from mii_phy import MiiReceiver
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import get_sim_args, run_on
from helpers import get_mii_rx_clk_phy, get_rgmii_rx_clk_phy
from helpers import get_mii_tx_clk_phy, get_rgmii_tx_clk_phy

def packet_checker(packet, phy):
    # Ignore the CRC bytes (-4)
    data = packet.data_bytes[:-4]

    if len(data) < 2:
        print "ERROR: packet doesn't contain enough data ({} bytes)".format(len(data))
        return

    step = data[1] - data[0]

    for i in range(len(data)-1):
        x = data[i+1] - data[i]
        x = x & 0xff;
        if x != step:
            print "ERROR: byte %d is %d more than byte %d (expected %d)." % (i+1, x, i, step)
            # Only print one error per packet
            break

def do_test(mac, rx_clk, rx_phy, tx_clk, tx_phy):
    resources = xmostest.request_resource("xsim")

    testname = 'test_timestamp_tx'

    binary = '{test}/bin/{mac}_{phy}/{test}_{mac}_{phy}.xe'.format(
        test=testname, mac=mac, phy=rx_phy.get_name())

    print "Running {test}: {mac} {phy} phy at {clk}".format(
        test=testname, mac=mac, phy=rx_phy.get_name(), clk=rx_clk.get_name())

    tester = xmostest.ComparisonTester(open('{test}.expect'.format(test=testname)),
                                     'lib_ethernet', 'basic_tests', testname,
                                       {'mac':mac, 'phy':rx_phy.get_name(), 'clk':rx_clk.get_name()},
                                       regexp=True)

    simargs = get_sim_args(testname, mac, rx_clk, rx_phy)
    tester.set_min_testlevel('nightly')
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[rx_clk, rx_phy, tx_clk, tx_phy],
                              tester=tester,
                              simargs=simargs)

def runtest():
    # Even though this is a TX-only test, both PHYs are needed in order to drive the mode pins for RGMII

    # Test 100 MBit - MII
    (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=packet_checker, test_ctrl='tile[0]:XS1_PORT_1C')
    (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(dut_exit_time=200000)
    if run_on(phy='mii', clk='25Mhz', mac='rt'):
        do_test('rt', rx_clk_25, rx_mii, tx_clk_25, tx_mii)

    # Test 100 MBit - RGMII
    (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=packet_checker,
                                                test_ctrl='tile[0]:XS1_PORT_1C')
    (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, dut_exit_time=200000)
    if run_on(phy='rgmii', clk='25Mhz', mac='rt'):
        do_test('rt', rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii)

    # Test 1000 MBit - RGMII
    (rx_clk_125, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_125MHz, packet_fn=packet_checker,
                                               test_ctrl='tile[0]:XS1_PORT_1C')
    (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, dut_exit_time=300000)
    if run_on(phy='rgmii', clk='125Mhz', mac='rt'):
        do_test('rt', rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii)
