#!/usr/bin/env python

import xmostest
import os
import random
import sys
from mii_clock import Clock
from mii_phy import MiiTransmitter, MiiReceiver
from rgmii_phy import RgmiiTransmitter, RgmiiReceiver
from mii_packet import MiiPacket
from helpers import do_rx_test, get_dut_mac_address, check_received_packet, run_on, args
from helpers import get_sim_args, create_if_needed, get_mii_tx_clk_phy, get_mii_rx_clk_phy
from helpers import get_rgmii_tx_clk_phy, get_rgmii_rx_clk_phy

tx_complete = False
rx_complete = False
num_test_packets = 75
test_ctrl = 'tile[0]:XS1_PORT_1C'

def start_test(phy):
    global tx_complete, rx_complete

    tx_complete = False
    rx_complete = False
    phy.num_packets = 0
    phy.num_bytes = 0
    phy.start_time = 0
    phy.end_time = 0

def set_tx_complete(phy):
    global tx_complete
    tx_complete = True

def packet_checker(packet, phy):
    global rx_complete

    time_now = phy.xsi.get_time()

    # The CRC is not included in the packet bytes
    num_packet_bytes = len(packet.get_packet_bytes()) + 4

    clock = phy.get_clock()
    bit_time = clock.get_bit_time()

    if not phy.start_time:
        packet_time = num_packet_bytes * 8 * bit_time
        phy.start_time = time_now - packet_time

    phy.num_packets += 1
    phy.num_bytes += num_packet_bytes

    time_delta = time_now - phy.start_time
    mega_bits_per_second = (phy.num_bytes * 8.0) / time_delta * 1000

    if phy.num_packets > 1:
        efficiency = ((((phy.num_bytes * 8) + ((phy.num_packets - 1) * 96)) * bit_time) / time_delta) * 100
    else:
        efficiency = (((phy.num_bytes * 8) * bit_time) / time_delta) * 100

    if phy.num_packets > num_test_packets:
        if rx_complete and tx_complete:

            # Allow time for the end of the packet to be received by the application
            # before signalling the end of the test
            phy.xsi._wait_until(phy.xsi.get_time() + 20000)

            # Indicate to the DUT receiver to print the byte count
            phy.xsi.drive_port_pins(test_ctrl, 1)
            if phy.end_time == 0:
                phy.end_time = phy.xsi.get_time()

            # Allow time for the byte count to be printed
            phy.xsi._wait_until(phy.end_time + 50000)
            phy.xsi.terminate()

    else:
        print "Packet {} received; bytes: {}, ifg: {} => {:.2f} Mb/s, efficiency {:.2f}%".format(
            phy.num_packets, num_packet_bytes, packet.get_ifg(), mega_bits_per_second, efficiency)

        if phy.num_packets == num_test_packets:
            rx_complete = True


def do_test(mac, rx_clk, rx_phy, tx_clk, tx_phy, seed):
    start_test(rx_phy)

    rand = random.Random()
    rand.seed(seed)

    # Generate an include file to define the seed
    with open(os.path.join("include", "seed.inc"), "w") as f:
        f.write("#define SEED {}".format(seed))

    resources = xmostest.request_resource("xsim")
    testname = 'test_time_rx_tx'
    level = 'nightly'

    binary = '{test}/bin/{mac}_{phy}/{test}_{mac}_{phy}.xe'.format(
        test=testname, mac=mac, phy=tx_phy.get_name())

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Running {test}: {phy} phy at {clk} (seed {seed})".format(
            test=testname, phy=tx_phy.get_name(), clk=tx_clk.get_name(), seed=seed)

    dut_mac_address = get_dut_mac_address()
    ifg = tx_clk.get_min_ifg()

    packets = []
    done = False
    num_data_bytes = 0
    while not done:
        do_small_packet = rand.randint(0, 100) > 30
        if do_small_packet:
            length = rand.randint(46, 100)
        else:
            length = rand.randint(46, 1500)

        burst_len = 1
        do_burst = rand.randint(0, 100) > 80
        if do_burst:
            burst_len = rand.randint(1, 16)

        for i in range(burst_len):
            packets.append(MiiPacket(rand,
                dst_mac_addr=dut_mac_address, inter_frame_gap=ifg, num_data_bytes=length
              ))

            # Add on the overhead of the packet header
            num_data_bytes += length + 14

            if len(packets) == num_test_packets:
                done = True
                break

    tx_phy.set_packets(packets)

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Sending {n} packets with {b} bytes at the DUT".format(n=len(packets), b=num_data_bytes)

    expect_folder = create_if_needed("expect")
    expect_filename = '{folder}/{test}_{mac}.expect'.format(
        folder=expect_folder, test=testname, mac=mac)
    create_expect(packets, expect_filename)
    tester = xmostest.ComparisonTester(open(expect_filename),
                                     'lib_ethernet', 'basic_tests', testname,
                                      {'mac':mac, 'phy':tx_phy.get_name(), 'clk':tx_clk.get_name()},
                                      regexp=True)

    tester.set_min_testlevel('nightly')

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[rx_clk, rx_phy, tx_clk, tx_phy],
                              tester=tester,
                              simargs=simargs)

def create_expect(packets, filename):
    """ Create the expect file for what packets should be reported by the DUT
    """
    with open(filename, 'w') as f:
        for i in range(num_test_packets):
            f.write("Packet \\d+ received; bytes: \\d+, ifg: \\d+\\.0 => \\d+\\.\\d+ Mb/s, efficiency \\d+\\.\\d+%\n")

        num_bytes = 0
        num_packets = 0
        for i,packet in enumerate(packets):
            if not packet.dropped:
                num_bytes += len(packet.get_packet_bytes())
                num_packets += 1
        f.write("Received {} packets, {} bytes\n".format(num_packets, num_bytes))

def runtest():
    random.seed(100)

    # Test 100 MBit - MII
    (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=packet_checker,
                                             test_ctrl=test_ctrl)
    (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(do_timeout=False, complete_fn=set_tx_complete,
                                             verbose=args.verbose, dut_exit_time=200000)
    if run_on(phy='mii', clk='25Mhz', mac='standard'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        do_test('standard', rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    if run_on(phy='mii', clk='25Mhz', mac='rt'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        do_test('rt', rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    if run_on(phy='mii', clk='25Mhz', mac='rt_hp'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        do_test('rt_hp', rx_clk_25, rx_mii, tx_clk_25, tx_mii, seed)

    # Test 100 MBit - RGMII
    (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=packet_checker,
                                                 test_ctrl=test_ctrl)
    (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, do_timeout=False,
                                                 complete_fn=set_tx_complete, verbose=args.verbose,
                                                 dut_exit_time=200000)
    if run_on(phy='rgmii', clk='25Mhz', mac='rt_hp'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        do_test('rt_hp', rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii, seed)

    # Test 1000 MBit - RGMII
    # The RGMII application cannot keep up with line-rate gigabit data
