#!/usr/bin/env python
import xmostest
import os
from mii_model import Clock, MiiTransmitter

def do_test(impl):
    resources = xmostest.request_resource("xsim")

    xmostest.build('test_etype_filter')

    binary = 'test_etype_filter/bin/%s/test_etype_filter_%s.xe' % (impl, impl)

    packets = [[0,1,2,3,4,5, 0, 0, 0, 0, 0, 0, 0x11, 0x11, 1, 2, 3, 4] + [0 for x in range(50)],
               [0,1,2,3,4,5, 0, 0, 0, 0, 0, 0, 0x22, 0x22, 5, 6, 7, 8] + [0 for x in range(60)]]

    txclock = Clock('tile[0]:XS1_PORT_1J', 25000000)
    receiver = MiiTransmitter('tile[0]:XS1_PORT_4E',
                              'tile[0]:XS1_PORT_1K',
                              txclock,
                              packets, verbose=True)

    tester = xmostest.pass_if_matches(open('etype_filter_test.expect'),
                                     'lib_ethernet', 'basic_tests',
                                      'etype_filter_test',{'impl':impl})

    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads = [txclock, receiver],
                              tester = tester)


def runtest():
    do_test("standard")
    do_test("rt")
