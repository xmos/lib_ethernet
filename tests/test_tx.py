#!/usr/bin/env python
import xmostest
import os
from mii_clock import Clock
from mii_phy import MiiReceiver
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import get_sim_args, get_mii_rx_clk_phy

def packet_checker(packet, phy):
    print "Packet received:"
    packet.dump()

    # Ignore the CRC bytes (-4)
    data = packet.data_bytes[:-4]

    step = data[1] - data[0]
    print "Step = {}.".format(step)

    for i in range(len(data)-1):
        x = data[i+1] - data[i]
        x = x & 0xff;
        if x != step:
            print "ERROR: byte %d is %d more than byte %d (expected %d)." % (i+1, x, i, step)
            # Only print one error per packet
            break

def do_test(impl, clk, phy):
    resources = xmostest.request_resource("xsim")

    testname = 'test_tx'

    binary = '{test}/bin/{impl}_{phy}/{test}_{impl}_{phy}.xe'.format(
        test=testname, impl=impl, phy=phy.get_name())

    print "Running {test}: {phy} phy at {clk}".format(
        test=testname, phy=phy.get_name(), clk=clk.get_name())

    tester = xmostest.ComparisonTester(open('{test}.expect'.format(test=testname)),
                                     'lib_ethernet', 'basic_tests', testname,
                                     {'impl':impl, 'phy':phy.get_name(), 'clk':clk.get_name()})

    simargs = get_sim_args(testname, impl, clk, phy)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[clk, phy],
                              tester=tester,
                              simargs=simargs)

def runtest():
    xmostest.build('test_tx')

    (clk_25, mii) = get_mii_rx_clk_phy(packet_fn=packet_checker, test_ctrl='tile[0]:XS1_PORT_1C')
    do_test('standard', clk_25, mii)
    do_test('rt', clk_25, mii)
