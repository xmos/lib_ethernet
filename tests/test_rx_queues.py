#!/usr/bin/env python
#
# A test for the high and low priority traffic queues in the MAC. It sends different
# packet types - high, low and other. The high priority traffic will be sent to the
# high priority queue in the MAC and should not be dropped. The low priority traffic
# is sent to the low priority MAC and can be dropped. All the other traffic will be
# dropped.
#
# Packets are sent in bursts where the same packet is repeated multiple times. The
# burst length is mostly 1.
#
# There test can limit the rate that the high priority traffic is sent. This takes
# into account the low priority and other traffic.
#

import xmostest
import random
import sys
from mii_clock import Clock
from mii_packet import MiiPacket
from helpers import packet_processing_time, get_dut_mac_address, args, run_on
from helpers import choose_small_frame_size, check_received_packet
from helpers import get_mii_tx_clk_phy, get_rgmii_tx_clk_phy, create_if_needed, get_sim_args

def choose_data_size(rand, data_len_min, data_len_max):
    return rand.randint(data_len_min, data_len_max)

class DataLimiter(object):

    HP_PACKET = 0
    LP_PACKET = 1
    OTHER_PACKET = 2

    def __init__(self, limited_hp_mbps, bit_time):
        self._limited_hp_mbps = limited_hp_mbps
        self._credit = 0
        self._bit_time = bit_time
        self._max_mbps = 1000 / bit_time

    def get_ifg(self, packet_type, num_data_bytes, tag):
        preamble_bytes = 8
        header_bytes = 14
        tag_bytes = 4 if tag else 0
        crc_bytes = 4
        ifg_bytes = 12
        num_packet_bytes = preamble_bytes + header_bytes + tag_bytes + num_data_bytes + crc_bytes + ifg_bytes
        packet_time = num_packet_bytes * 8 * self._bit_time

        self._credit += packet_time

        if packet_type == self.HP_PACKET:
            # Determine how long the packet should take at the limited rate
            data_limited_time = packet_time * self._max_mbps / self._limited_hp_mbps

            self._credit -= data_limited_time

            if self._credit < 0:
                ifg_time = -self._credit + ifg_bytes * 8 * self._bit_time
                self._credit = 0
            else:
                ifg_time = ifg_bytes * 8 * self._bit_time
        else:
            data_limited_time = packet_time
            ifg_time = ifg_bytes * 8 * self._bit_time

        #print "Packet {n} bytes {ns} ns, limited means {scaled}ns -> {ifg}".format(
        #    n=num_data_bytes, ns=packet_time, scaled=data_limited_time, ifg=ifg_time)

        return ifg_time

class RxLpControl(xmostest.SimThread):

    def __init__(self, rx_lp_ctl, bit_time, initial_value, randomise, seed):
        self._rx_lp_ctl = rx_lp_ctl
        self._bit_time = bit_time
        self._initial_value = initial_value
        self._randomise = randomise
        self._rand = random.Random()
        self._rand.seed(seed)

    def run(self):
        xsi = self.xsi

        xsi.drive_port_pins(self._rx_lp_ctl, self._initial_value)

        if not self._randomise:
            return

        while True:
            delay = self._rand.randint(1, 10000) * self._bit_time
            self.wait_until(xsi.get_time() + delay)

            # Create a high pulse
            xsi.drive_port_pins(self._rx_lp_ctl, 1)
            self.wait_until(xsi.get_time() + 100)
            xsi.drive_port_pins(self._rx_lp_ctl, 0)


def do_test(mac, tx_clk, tx_phy, seed,
            level='nightly',
            num_packets=200,
            weight_hp=50, weight_lp=50, weight_other=50,
            data_len_min=46, data_len_max=500,
            weight_tagged=50, weight_untagged=50,
            max_hp_mbps=1000,
            # The low-priority packets can go to either client or both
            lp_mac_addresses=[[1,2,3,4,5,6],
                              [2,3,4,5,6,7],
                              [0xff,0xff,0xff,0xff,0xff,0xff]]):

    rand = random.Random()
    rand.seed(seed)

    bit_time = tx_phy.get_clock().get_bit_time()
    rxLpControl1 = RxLpControl('tile[0]:XS1_PORT_1D', bit_time, 0, True, rand.randint(0, sys.maxint))
    rxLpControl2 = RxLpControl('tile[0]:XS1_PORT_1E', bit_time, 0, True, rand.randint(0, sys.maxint))

    resources = xmostest.request_resource("xsim")
    testname = 'test_rx_queues'

    binary = '{test}/bin/{mac}_{phy}/{test}_{mac}_{phy}.xe'.format(
        test=testname, mac=mac, phy=tx_phy.get_name())

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Running {test}: {phy} phy at {clk} (seed {seed})".format(
            test=testname, phy=tx_phy.get_name(), clk=tx_clk.get_name(), seed=seed)

    hp_mac_address = [0,1,2,3,4,5]
    hp_seq_id = 0
    hp_data_bytes = 0
    lp_seq_id = 0
    lp_data_bytes = 0
    other_mac_address = [12,13,14,15,16,17]
    other_seq_id = 0
    other_data_bytes = 0

    packets = []
    done = False

    limiter = DataLimiter(max_hp_mbps, bit_time)
    total_weight_tag = weight_tagged + weight_untagged
    total_weight_tc = weight_hp + weight_lp + weight_other
    while not done:
        if (rand.randint(0, total_weight_tag) < weight_tagged):
            tag = [0x81, 0x00, rand.randint(0,0xff), rand.randint(0, 0xff)]
        else:
            tag = None

        mac_choice = rand.randint(0, total_weight_tc - 1)
        if (mac_choice < weight_lp):
            dst_mac_addr = rand.choice(lp_mac_addresses)
        elif (mac_choice < weight_hp + weight_lp):
            dst_mac_addr = hp_mac_address
        else:
            dst_mac_addr = other_mac_address

        frame_size = choose_data_size(rand, data_len_min, data_len_max)

        if (rand.randint(0,100) > 95):
            burst_len = rand.randint(2,20)
        else:
            burst_len = 1

        for j in range(burst_len):
            # The seq_ids are effectively packet counts
            if (hp_seq_id + lp_seq_id + other_seq_id) == num_packets:
                done = True
                break

            if dst_mac_addr in lp_mac_addresses:
                packet_type = DataLimiter.LP_PACKET
                seq_id = lp_seq_id
                lp_seq_id += 1
                lp_data_bytes += frame_size + 14
                if tag:
                    lp_data_bytes += 4
            elif dst_mac_addr == hp_mac_address:
                packet_type = DataLimiter.HP_PACKET
                seq_id = hp_seq_id
                hp_seq_id += 1
                hp_data_bytes += frame_size + 14
                if tag:
                    hp_data_bytes += 4
            else:
                packet_type = DataLimiter.OTHER_PACKET
                seq_id = other_seq_id
                other_seq_id += 1
                other_data_bytes += frame_size + 14
                if tag:
                    other_data_bytes += 4

            ifg = limiter.get_ifg(packet_type, frame_size, tag)

            packets.append(MiiPacket(rand,
                dst_mac_addr=dst_mac_addr,
                create_data_args=['same', (seq_id, frame_size)],
                vlan_prio_tag=tag,
                inter_frame_gap=ifg
            ))


    tx_phy.set_packets(packets)

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Sending {n} hp packets with {b} bytes data".format(n=hp_seq_id, b=hp_data_bytes)
        print "Sending {n} lp packets with {b} bytes hp data".format(n=lp_seq_id, b=lp_data_bytes)
        print "Sending {n} other packets with {b} bytes hp data".format(n=other_seq_id, b=other_data_bytes)

    expect_folder = create_if_needed("expect")
    expect_filename = '{folder}/{test}_{mac}_{phy}.expect'.format(
        folder=expect_folder, test=testname, mac=mac, phy=tx_phy.get_name())
    create_expect(packets, expect_filename, hp_mac_address)
    tester = xmostest.ComparisonTester(open(expect_filename),
                                     'lib_ethernet', 'basic_tests', testname,
                                      {'mac':mac, 'phy':tx_phy.get_name(), 'clk':tx_clk.get_name(),
                                       'max_hp_mbps':max_hp_mbps,
                                       'len_min':data_len_min, 'len_max':data_len_max,
                                       'w_hp':weight_hp, 'w_lp':weight_lp, 'w_other':weight_other,
                                       'n_packets':num_packets},
                                      regexp=True)

    tester.set_min_testlevel(level)

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[tx_clk, tx_phy, rxLpControl1, rxLpControl2],
                              tester=tester,
                              simargs=simargs)

def create_expect(packets, filename, hp_mac_address):
    """ Create the expect file for what packets should be reported by the DUT
    """
    num_bytes_hp = 0

    for i,packet in enumerate(packets):
        if packet.dropped:
            continue

        if (packet.dst_mac_addr == hp_mac_address):
            num_bytes_hp += len(packet.get_packet_bytes())

    with open(filename, 'w') as f:
        num_bytes = 0
        f.write("Received {} hp bytes\n".format(num_bytes_hp))
        f.write("LP client 1 received \d+ bytes\n")
        f.write("LP client 2 received \d+ bytes\n")


def runtest():

    if args.data_len_max < args.data_len_min:
        print "ERROR: Invalid arguments, data_len_max ({max}) cannot be less than data_len_min ({min})".format(
            min=args.data_len_min, max=args.data_len_max)
        return

    random.seed(args.seed if args.seed is not None else 1)

    # Test 100 MBit - MII
    (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(test_ctrl='tile[0]:XS1_PORT_1C', expect_loopback=False,
                                             verbose=args.verbose)
    if run_on(phy='mii', clk='25Mhz', mac='rt'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        # Test having every packet going to both LP receivers
        do_test('rt', tx_clk_25, tx_mii, seed,
                level='smoke',
                num_packets=200,
                weight_hp=0, weight_lp=100, weight_other=0,
                data_len_min=46, data_len_max=46,
                weight_tagged=args.weight_tagged, weight_untagged=args.weight_untagged,
                max_hp_mbps=100,
                lp_mac_addresses=[[0xff,0xff,0xff,0xff,0xff,0xff]])

        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        do_test('rt', tx_clk_25, tx_mii, seed,
                num_packets=200,
                weight_hp=100, weight_lp=0, weight_other=0,
                data_len_min=200, data_len_max=200,
                weight_tagged=args.weight_tagged, weight_untagged=args.weight_untagged,
                max_hp_mbps=100)

    # Test 100 MBit - RGMII
    (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, test_ctrl='tile[0]:XS1_PORT_1C',
                                                 expect_loopback=False, verbose=args.verbose)
    if run_on(phy='rgmii', clk='25Mhz', mac='rt'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        do_test('rt', tx_clk_25, tx_rgmii, seed,
                num_packets=args.num_packets,
                weight_hp=args.weight_hp, weight_lp=args.weight_lp, weight_other=args.weight_other,
                data_len_min=args.data_len_min, data_len_max=args.data_len_max,
                weight_tagged=args.weight_tagged, weight_untagged=args.weight_untagged,
                max_hp_mbps=100)

    # Test 1GBit - RGMII
    (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, test_ctrl='tile[0]:XS1_PORT_1C',
                                                  expect_loopback=False, verbose=args.verbose)
    if run_on(phy='rgmii', clk='125Mhz', mac='rt'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        do_test('rt', tx_clk_125, tx_rgmii, seed,
                num_packets=200,
                weight_hp=100, weight_lp=0, weight_other=0,
                data_len_min=46, data_len_max=46,
                weight_tagged=args.weight_tagged, weight_untagged=args.weight_untagged,
                max_hp_mbps=300)

        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        do_test('rt', tx_clk_125, tx_rgmii, seed,
                num_packets=200,
                weight_hp=100, weight_lp=0, weight_other=0,
                data_len_min=200, data_len_max=200,
                weight_tagged=args.weight_tagged, weight_untagged=args.weight_untagged,
                max_hp_mbps=600)

        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        do_test('rt', tx_clk_125, tx_rgmii, seed,
                num_packets=args.num_packets,
                weight_hp=args.weight_hp, weight_lp=args.weight_lp, weight_other=args.weight_other,
                data_len_min=args.data_len_min, data_len_max=args.data_len_max,
                weight_tagged=args.weight_tagged, weight_untagged=args.weight_untagged,
                max_hp_mbps=args.max_hp_mbps)
