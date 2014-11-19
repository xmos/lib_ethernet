#!/usr/bin/env python
import xmostest
import os
from mii_model import Clock, MiiTransmitter

def do_test(impl):
    resources = xmostest.request_resource("xsim")

    xmostest.build('test_rx')

    binary = 'test_rx/bin/%s/test_rx_%s.xe' % (impl, impl)

    packets = [[0,1,2,3,4,5] + [i for i in range(80)],
               [0,1,2,3,4,5] + [5*i&0xff for i in range(60)],
               [0,1,2,3,4,5] + [7*i&0xff for i in range(1508)]]

    rxclock = Clock('tile[0]:XS1_PORT_1J', 25000000)
    receiver = MiiTransmitter('tile[0]:XS1_PORT_4E',
                              'tile[0]:XS1_PORT_1K',
                              rxclock,
                              packets)

    tester = xmostest.pass_if_matches(open('rx_test.expect'),
                                     'lib_ethernet', 'basic_tests',
                                      'rx_test',{'impl':impl})

    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads = [rxclock, receiver],
                              tester = tester)


def runtest():
    do_test("standard")
    do_test("rt")
