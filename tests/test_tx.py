#!/usr/bin/env python
import xmostest
import os
from mii_clock import Clock
from mii_phy import MiiReceiver
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket


def packet_checker(packet):
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

def do_test(impl):
    resources = xmostest.request_resource("xsim")

    binary = 'test_tx/bin/{impl}/test_tx_{impl}.xe'.format(impl=impl)

    clock_25 = Clock('tile[0]:XS1_PORT_1I', Clock.CLK_25MHz)
    phy = MiiReceiver('tile[0]:XS1_PORT_1A',
                      'tile[0]:XS1_PORT_4F',
                      'tile[0]:XS1_PORT_1L',
                      clock_25,
                      print_packets=False,
                      packet_fn=packet_checker)

    tester = xmostest.pass_if_matches(open('test_tx.expect'),
                                     'lib_ethernet', 'basic_tests',
                                      'tx_test', {'impl':impl})

    log_folder = "logs"
    if not os.path.exists(log_folder):
        os.makedirs(log_folder)

    filename = "{log}/xsim_trace_test_tx_{impl}".format(log=log_folder, impl=impl)
    trace_args = "--trace-to {0}.txt".format(filename)
    vcd_args = '--vcd-tracing "-o {0}.vcd -tile tile[0] -ports -instructions -functions -cycles"'.format(filename)

    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[clock_25, phy],
                              tester=tester,
                              simargs=[trace_args, vcd_args])

def runtest():
    do_test('standard')
    do_test('rt')
