#!/usr/bin/env python

import xmostest
import os
import random
import sys
from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address, check_received_packet, packet_processing_time
from helpers import get_sim_args, get_mii_tx_clk_phy, get_rgmii_tx_clk_phy, run_on

def do_test(mac, tx_clk, tx_phy):
    resources = xmostest.request_resource("xsim")

    testname = 'test_vlan_strip'

    binary = '{test}/bin/{mac}_{phy}/{test}_{mac}_{phy}.xe'.format(
        test=testname, mac=mac, phy=tx_phy.get_name())

    print "Running {test}: {phy} phy at {clk}".format(
        test=testname, phy=tx_phy.get_name(), clk=tx_clk.get_name())

    rand = random.Random()

    dut_mac_address = get_dut_mac_address()
    packets = [
        MiiPacket(rand, dst_mac_addr=dut_mac_address, src_mac_addr=[0 for x in range(6)],
                  ether_len_type=[0x11, 0x11], inter_frame_gap=packet_processing_time(tx_phy, 64, mac)*2,
                  vlan_prio_tag=[0x81, 0x00, 0x00, 0x00], data_bytes=[1,2,3,4] + [0 for x in range(60)]),
        MiiPacket(rand, dst_mac_addr=dut_mac_address, src_mac_addr=[0 for x in range(6)],
                  ether_len_type=[0x22, 0x22], inter_frame_gap=packet_processing_time(tx_phy, 64, mac)*2,
                  data_bytes=[5,6,7,8] + [0 for x in range(60)]),
        MiiPacket(rand, dst_mac_addr=dut_mac_address, src_mac_addr=[0 for x in range(6)],
                  ether_len_type=[0x33, 0x33], vlan_prio_tag=[0x81, 0x00, 0x00, 0x00],
                  inter_frame_gap=packet_processing_time(tx_phy, 64, mac)*2, data_bytes=[4,3,2,1] + [0 for x in range(60)]),
        MiiPacket(rand, dst_mac_addr=dut_mac_address, src_mac_addr=[0 for x in range(6)],
                  ether_len_type=[0x44, 0x44], inter_frame_gap=packet_processing_time(tx_phy, 64, mac)*2,
                  data_bytes=[8,7,6,5] + [0 for x in range(60)])
      ]

    tx_phy.set_packets(packets)

    tester = xmostest.ComparisonTester(open('test_vlan_strip_{phy}_{mac}.expect'.format(phy=tx_phy.get_name(), mac=mac)),
                                     'lib_ethernet', 'basic_tests', testname,
                                      {'mac':mac, 'phy':tx_phy.get_name(), 'clk':tx_clk.get_name()})

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy)
    tester.set_min_testlevel('nightly')
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[tx_clk, tx_phy],
                              tester=tester,
                              simargs=simargs)

def runtest():
    random.seed(1)

    # Test 100 MBit - MII
    (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(verbose=True, test_ctrl="tile[0]:XS1_PORT_1A")
    if run_on(phy='mii', clk='25Mhz', mac='standard'):
        do_test('standard', tx_clk_25, tx_mii)
    if run_on(phy='mii', clk='25Mhz', mac='rt'):
        do_test('rt', tx_clk_25, tx_mii)

    # Test 100 MBit - RGMII
    (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, verbose=True, test_ctrl="tile[0]:XS1_PORT_1A")
    if run_on(phy='rgmii', clk='25Mhz', mac='rt'):
        do_test('rt', tx_clk_25, tx_rgmii)

    # Test 1000 MBit - RGMII
    (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, verbose=True, test_ctrl="tile[0]:XS1_PORT_1A")
    if run_on(phy='rgmii', clk='125Mhz', mac='rt'):
        do_test('rt', tx_clk_125, tx_rgmii)
