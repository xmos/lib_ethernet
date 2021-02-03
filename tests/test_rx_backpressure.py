#!/usr/bin/env python
# Copyright (c) 2018-2021, XMOS Ltd, All rights reserved

import random
import xmostest
import os
import re
import sys
from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import get_sim_args, packet_processing_time, get_dut_mac_address
from helpers import choose_small_frame_size, check_received_packet, args, run_on
from helpers import get_mii_rx_clk_phy, get_mii_tx_clk_phy, get_rgmii_rx_clk_phy, get_rgmii_tx_clk_phy

class OutputChecker(xmostest.Tester):
    """ Check that every line from the DUT is an increasing packet size received
    """

    def __init__(self, product, group, test, config={}, env={},
                 regexp=False, ignore=[], ordered=True):
        super(OutputChecker, self).__init__()
        self.register_test(product, group, test, config)
        self._test = (product, group, test, config, env)

    def record_failure(self, failure_reason):
        # Append a newline if there isn't one already
        if not failure_reason.endswith('\n'):
            failure_reason += '\n'
        self.failures.append(failure_reason)
        sys.stderr.write("ERROR: %s" % failure_reason)
        self.result = False

    def run(self, output):
        (product, group, test, config, env) = self._test
        self.result = True
        self.failures = []
        line_num = 0
        last_packet_len = 0

        for i in range(len(output)):
            line_num += 1
            if not re.match("Received \d+",output[i].strip()):
                self.record_failure(("Line %d of output does not match expected\n" % line_num))
                continue

            packet_len = int(output[i].split()[1])
            if packet_len <= last_packet_len:
                self.record_failure(("Line %d of output contains invalid packet size %d\n" % (line_num, packet_len)))
                continue

            last_packet_len = packet_len

        if (line_num == 0):
            self.record_failure("No packets seen")
        output = {'output':''.join(output)}
        if not self.result:
            output['failures'] = ''.join(self.failures)
        xmostest.set_test_result(product, group, test, config, self.result,
                                 output=output, env=env)


def do_rx_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, test_file, seed,
               level='nightly', extra_tasks=[]):

    testname,extension = os.path.splitext(os.path.basename(test_file))

    resources = xmostest.request_resource("xsim")

    binary = 'test_rx_backpressure/bin/{mac}_{phy}_{arch}/test_rx_backpressure_{mac}_{phy}_{arch}.xe'.format(
        mac=mac, phy=tx_phy.get_name(), arch=arch)

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Running {test}: {mac} mac, {phy} phy, {arch} arch sending {n} packets at {clk} (seed {seed})".format(
            test=testname, n=len(packets), mac=mac,
            phy=tx_phy.get_name(), arch=arch, clk=tx_clk.get_name(), seed=seed)

    tx_phy.set_packets(packets)

    tester = OutputChecker('lib_ethernet', 'basic_tests', testname,
                           {'mac':mac, 'phy':tx_phy.get_name(), 'clk':tx_clk.get_name(), 'arch':arch})

    tester.set_min_testlevel(level)

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy, arch)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[rx_clk, rx_phy, tx_clk, tx_phy] + extra_tasks,
                              tester=tester,
                              simargs=simargs)

def do_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    rand = random.Random()
    rand.seed(seed)

    dut_mac_address = get_dut_mac_address()
    broadcast_mac_address = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff]

    # The inter-frame gap is to give the DUT time to print its output
    packets = []

    # Send enough basic frames to ensure the buffers in the DUT have wrapped
    for i in range(200):
        packets.append(MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            create_data_args=['step', (i, i+36)],
        ))

    do_rx_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, packets, __file__, seed,
               level='nightly')

def runall_rx(test_fn):
    # Test 100 MBit
    for arch in ['xs1', 'xs2']:
        (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=check_received_packet)
        (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(verbose=args.verbose, test_ctrl="tile[0]:XS1_PORT_1A")
        if run_on(phy='mii', clk='25Mhz', mac='standard', arch=arch):
            seed = args.seed if args.seed else random.randint(0, sys.maxint)
            test_fn('standard', arch, rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

        # Only run on the rt MAC. The HP queue does not support lots of backpressure
        # as it expects the client to consume packets or else it locks up and
        # everything goes wrong
        if run_on(phy='mii', clk='25Mhz', mac='rt', arch=arch):
            seed = args.seed if args.seed else random.randint(0, sys.maxint)
            test_fn('rt', arch, rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    # Test 100 MBit - RGMII - only supported on XS2
    (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=check_received_packet)
    (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, verbose=args.verbose, test_ctrl="tile[0]:XS1_PORT_1A")
    if run_on(phy='rgmii', clk='25Mhz', mac='rt', arch='xs2'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn('rt', 'xs2', rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii, seed)

    # Test 1000 MBit - RGMII - only supported on XS2
    (rx_clk_125, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_125MHz, packet_fn=check_received_packet)
    (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, verbose=args.verbose, test_ctrl="tile[0]:XS1_PORT_1A")
    if run_on(phy='rgmii', clk='125Mhz', mac='rt', arch='xs2'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        test_fn('rt', 'xs2', rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii, seed)

def runtest():
    random.seed(1)
    runall_rx(do_test)
