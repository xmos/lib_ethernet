#!/usr/bin/env python
import xmostest
import os
from mii_clock import Clock
from mii_phy import MiiReceiver
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket


def packet_checker(packet):
    # Ignore the CRC (-4)
    data = packet.data_bytes[:-4]
    
    print "Packet received, len={}.".format(len(data))
    step = data[1] - data[0]
    print "Step = {}.".format(step)

    for i in range(len(data)-1):
        x = data[i+1] - data[i]
        x = x & 0xff;
        if x != step:
            print "ERROR: byte %d is %d more than byte %d (expected %d)." % (i+1, x, i, step)
            # Only print one error per packet
            break

def do_test(impl):
    resources = xmostest.request_resource("xsim")

    binary = 'test_tx/bin/%s/test_tx_%s.xe' % (impl, impl)

    clock_25 = Clock('tile[0]:XS1_PORT_1I', Clock.CLK_25MHz)
    phy = MiiReceiver('tile[0]:XS1_PORT_4F',
                      'tile[0]:XS1_PORT_1L',
                      clock_25,
                      print_packets=False,
                      packet_fn=packet_checker,
                      terminate_after=2)

    tester = xmostest.pass_if_matches(open('tx_test.expect'),
                                     'lib_ethernet', 'basic_tests',
                                      'tx_test', {'impl':impl})

    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads = [clock_25, phy],
                              tester = tester)

def runtest():
    do_test('standard')
    do_test('rt')
