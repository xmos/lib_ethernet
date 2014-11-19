#!/usr/bin/env python
import xmostest
import os
from mii_model import Clock, MiiReceiver

def packet_checker(packet):
    print "Packet received, len=%d." % (len(packet))
    step = packet[1] - packet[0]
    print "Step = %d." % step
    for i in range(len(packet)-1):
        x = packet[i+1] - packet[i]
        x = x & 0xff;
        if x != step:
            print "ERROR: byte %d is %d more than byte %d (expected %d)." % (i+1, x, i, step)

def do_test(impl):
    resources = xmostest.request_resource("xsim")

    xmostest.build('test_tx')

    binary = 'test_tx/bin/%s/test_tx_%s.xe' % (impl, impl)

    txclock = Clock('tile[0]:XS1_PORT_1I', 25000000)
    receiver = MiiReceiver('tile[0]:XS1_PORT_4F',
                           'tile[0]:XS1_PORT_1L',
                           txclock,
                           print_packets = False,
                           packet_fn = packet_checker,
                           terminate_after = 2)

    tester = xmostest.pass_if_matches(open('tx_test.expect'),
                                     'lib_ethernet', 'basic_tests',
                                      'tx_test', {'impl':impl})

    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads = [txclock, receiver],
                              tester = tester)

def runtest():
    do_test('standard')
    do_test('rt')
