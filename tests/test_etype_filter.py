#!/usr/bin/env python
import xmostest
import os
import random
from mii_clock import Clock
from mii_phy import MiiTransmitter
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import do_rx_test


def do_test(impl, clk, phy):
    resources = xmostest.request_resource("xsim")

    binary = 'test_etype_filter/bin/{impl}_{phy}/test_etype_filter_{impl}_{phy}.xe'.format(
        impl=impl, phy=phy.get_name())

    dut_mac_address = [0,1,2,3,4,5]
    packets = [
        MiiPacket(dst_mac_addr=dut_mac_address, src_mac_addr=[0 for x in range(6)],
                  ether_len_type=[0x11, 0x11], data_bytes=[1,2,3,4] + [0 for x in range(50)]),
        MiiPacket(dst_mac_addr=dut_mac_address, src_mac_addr=[0 for x in range(6)],
                  ether_len_type=[0x22, 0x22], data_bytes=[5,6,7,8] + [0 for x in range(60)])
      ]

    phy.set_packets(packets)
    
    tester = xmostest.pass_if_matches(open('test_etype_filter.expect'),
                                     'lib_ethernet', 'basic_tests',
                                      'etype_filter_test', {'impl':impl, 'phy':phy.get_name(), 'clk':clk.get_name()})

    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads = [clk, phy],
                              tester = tester)


def runtest():
    random.seed(1)
    
    clock_25 = Clock('tile[0]:XS1_PORT_1J', Clock.CLK_25MHz)
    mii = MiiTransmitter('tile[0]:XS1_PORT_1A',
                         'tile[0]:XS1_PORT_4E',
                         'tile[0]:XS1_PORT_1K',
                         clock_25,
                         verbose=True)

    do_test("standard", clock_25, mii)
    do_test("rt", clock_25, mii)
