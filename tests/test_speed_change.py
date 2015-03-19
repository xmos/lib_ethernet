#!/usr/bin/env python

import xmostest
import random
import sys
from mii_packet import MiiPacket
from mii_clock import Clock
from helpers import do_rx_test, packet_processing_time, get_dut_mac_address, args
from helpers import choose_small_frame_size, check_received_packet, runall_rx, run_on
from helpers import get_rgmii_tx_clk_phy, create_if_needed, get_sim_args

initial_delay = 100000

class ClockControl(xmostest.SimThread):
    """ A class to control the clocks, alternating between the 25 and 125 MHz clocks
        being active.
    """

    def __init__(self, speed_change_time, tx_clk_25, tx_rgmii_25, tx_clk_125, tx_rgmii_125):
        self.speed_change_time = speed_change_time
        self.tx_clk_25 = tx_clk_25
        self.tx_rgmii_25 = tx_rgmii_25
        self.tx_clk_125 = tx_clk_125
        self.tx_rgmii_125 = tx_rgmii_125

    def run(self):
        xsi = self.xsi

        # Setup the initial state (25MHz)
        self.tx_clk_25.start()
        self.tx_clk_125.stop()
        # Drive the status onto the data pins
        self.tx_rgmii_25.set_data(self.tx_rgmii_25._phy_status)

        
        # Change clock speeds 1/2 window before the packets
        self.wait_until(xsi.get_time() + initial_delay - (self.speed_change_time / 2))
        
        while True:
            # Wait for packets to be sent
            self.wait_until(xsi.get_time() + self.speed_change_time)

            # Go to 125MHz
            self.tx_clk_25.stop()
            self.tx_clk_125.start()
            self.tx_rgmii_125.set_data(self.tx_rgmii_125._phy_status)

            # Wait for packets to be sent
            self.wait_until(xsi.get_time() + self.speed_change_time)

            # Return to 25MHz
            self.tx_clk_25.start()
            self.tx_clk_125.stop()
            self.tx_rgmii_25.set_data(self.tx_rgmii_25._phy_status)


def create_packets(rand, clk, dut_mac_address, speed_change_time,
                   num_packets, initial_ifg, data_base):
    ifg = initial_ifg
    bit_time = clk.get_bit_time()
    
    packets = []

    for i in range(num_packets):
        packet = MiiPacket(rand,
            dst_mac_addr=dut_mac_address,
            create_data_args=['same', (data_base + i*2, choose_small_frame_size(rand))],
            inter_frame_gap=ifg
        )
        # The packet time includes its IFG, so discount that
        ifg = 2 * speed_change_time - (packet.get_packet_time(bit_time) - ifg)
        packets.append(packet)

    return packets
        

def do_test(mac, tx_clk_25, tx_rgmii_25, tx_clk_125, tx_rgmii_125, seed):
    rand = random.Random()
    rand.seed(seed)

    # The time to run at each speed before switching to the other
    speed_change_time = 2000000

    resources = xmostest.request_resource("xsim")
    testname = 'test_speed_change'
    level = 'nightly'

    binary = '{test}/bin/{mac}_rgmii/{test}_{mac}_rgmii.xe'.format(
        test=testname, mac=mac)

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Running {test}: rgmii phy (seed {seed})".format(
            test=testname, seed=seed)

    dut_mac_address = get_dut_mac_address()

    # The inter-frame gap is to give the DUT time to print its output
    packets_25 = create_packets(rand, tx_clk_25, dut_mac_address, speed_change_time,
                                1, 0, 0)
    packets_125 = create_packets(rand, tx_clk_125, dut_mac_address, speed_change_time,
                                 1, speed_change_time, 1)

    tx_rgmii_25.set_packets(packets_25)
    tx_rgmii_125.set_packets(packets_125)

    expect_folder = create_if_needed("expect")
    expect_filename = '{folder}/{test}_{mac}_rgmii.expect'.format(
        folder=expect_folder, test=testname, mac=mac)
    create_expect(expect_filename, packets_25, packets_125)
    tester = xmostest.ComparisonTester(open(expect_filename),
                                        'lib_ethernet', 'basic_tests', testname,
                                        {'mac':mac, 'phy':'rgmii'})

    tester.set_min_testlevel(level)

    clock_control = ClockControl(speed_change_time, tx_clk_25, tx_rgmii_25,
                                 tx_clk_125, tx_rgmii_125)
    
    simargs = get_sim_args(testname, mac, tx_clk_25, tx_rgmii_25)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[tx_clk_25, tx_rgmii_25,
                                          tx_clk_125, tx_rgmii_125,
                                          clock_control],
                              tester=tester,
                              simargs=simargs)

def create_expect(filename, packets_25, packets_125):
    """ Create the expect file for what packets should be reported by the DUT
    """
    num_packets = 0
    num_data_bytes = 0
    for packet in packets_25 + packets_125:
        num_packets += 1
        num_data_bytes += len(packet.get_packet_bytes())
    
    with open(filename, 'w') as f:
        f.write("Received {} packets, {} bytes\n".format(num_packets, num_data_bytes))

def runtest():
    random.seed(1)
    
    (tx_clk_25, tx_rgmii_25) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, initial_delay=initial_delay,
                                                  expect_loopback=False, verbose=args.verbose, dut_exit_time=5000000)
    (tx_clk_125, tx_rgmii_125) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, initial_delay=initial_delay,
                                                      test_ctrl='tile[0]:XS1_PORT_1C',
                                                      expect_loopback=False, verbose=args.verbose, dut_exit_time=5000000)

    seed = args.seed if args.seed else random.randint(0, sys.maxint)
    if run_on(mac='rt'):
        do_test('rt', tx_clk_25, tx_rgmii_25, tx_clk_125, tx_rgmii_125, seed)

    seed = args.seed if args.seed else random.randint(0, sys.maxint)
    if run_on(mac='rt_hp'):
        do_test('rt_hp', tx_clk_25, tx_rgmii_25, tx_clk_125, tx_rgmii_125, seed)
