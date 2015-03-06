#!/usr/bin/env python
#
import xmostest
import random
import sys
from mii_clock import Clock
from mii_packet import MiiPacket
from helpers import packet_processing_time, get_dut_mac_address, args, run_on
from helpers import choose_small_frame_size, check_received_packet
from helpers import get_mii_tx_clk_phy, get_rgmii_tx_clk_phy, create_if_needed, get_sim_args

debug_fill = 0

def choose_data_size(rand, data_len_min, data_len_max):
    return rand.randint(data_len_min, data_len_max)

def get_min_packet_time(bit_time):
    preamble_bytes = 8
    header_bytes = 14
    crc_bytes = 4
    ifg_bytes = 12
    min_data_bytes = 46
    total_bytes = preamble_bytes + header_bytes + min_data_bytes + crc_bytes + ifg_bytes
    return total_bytes * 8 * bit_time


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


class PacketFiller:

    TYPE_NONE = 0
    TYPE_LP = 1
    TYPE_OTHER = 2
    
    none_mac_address = [0,0,0,0,0,0]
    lp_mac_address = [1,1,1,1,1,1]
    lp_seq_id = 0
    lp_data_bytes = 0
    other_mac_address = [2,2,2,2,2,2]
    other_seq_id = 0
    other_data_bytes = 0

    def __init__(self, weight_none, weight_lp, weight_other, weight_tagged, weight_untagged,
                 data_len_min, data_len_max, bit_time):
        self.weight_none = weight_none
        self.weight_lp = weight_lp
        self.weight_other = weight_other
        self.weight_tagged = weight_tagged
        self.weight_untagged = weight_untagged
        self.data_len_min = data_len_min
        self.data_len_max = data_len_max

        self.total_weight_tag = weight_tagged + weight_untagged
        self.total_weight_tc = weight_none + weight_lp + weight_other

        self.min_packet_time = get_min_packet_time(bit_time)
        self.bit_time = bit_time

    def fill_gap(self, rand, packets, gap_size, last_packet_end, ifg):
        min_ifg = 96 * self.bit_time

        if debug_fill:
            print "fill_gap {}, {} / {} / {}".format(last_packet_end, ifg, gap_size, self.min_packet_time)
        
        while gap_size > self.min_packet_time:

            if (rand.randint(0, self.total_weight_tag) < self.weight_tagged):
                tag = [0x81, 0x00, rand.randint(0,0xff), rand.randint(0, 0xff)]
            else:
                tag = None

            mac_choice = rand.randint(0, self.total_weight_tc - 1)
            if (mac_choice < self.weight_none):
                dst_mac_addr = self.none_mac_address
            elif (mac_choice < self.weight_none + self.weight_lp):
                dst_mac_addr = self.lp_mac_address
            else:
                dst_mac_addr = self.other_mac_address

            frame_size = choose_data_size(rand, self.data_len_min, self.data_len_max)
            
            if (rand.randint(0,100) > 30):
                burst_len = rand.randint(1,20)
            else:
                burst_len = 1

            for j in range(burst_len):
                # The seq_ids are effectively packet counts
                if (gap_size < self.min_packet_time):
                    break
        
                if dst_mac_addr == self.none_mac_address:
                    packet_type = self.TYPE_NONE
                    seq_id = 0
                elif dst_mac_addr == self.lp_mac_address:
                    packet_type = self.TYPE_LP
                    seq_id = self.lp_seq_id
                    self.lp_seq_id += 1
                    self.lp_data_bytes += frame_size + 14
                    if tag:
                        self.lp_data_bytes += 4
                else:
                    packet_type = self.TYPE_OTHER
                    seq_id = self.other_seq_id
                    self.other_seq_id += 1
                    self.other_data_bytes += frame_size + 14
                    if tag:
                        self.other_data_bytes += 4

                packet = MiiPacket(rand,
                    dst_mac_addr=dst_mac_addr,
                    create_data_args=['same', (seq_id, frame_size)],
                    vlan_prio_tag=tag,
                    inter_frame_gap=ifg)

                packet_time = packet.get_packet_time(self.bit_time)

                if debug_fill:
                    print "FILLER {} -> {} ({})".format(last_packet_end, last_packet_end + packet_time, frame_size)

                gap_size -= packet_time
                last_packet_end += packet_time
                
                if packet_type == self.TYPE_NONE:
                    # Simply skip this packet
                    ifg += packet_time
                else:
                    packets.append(packet)
                    ifg = rand.randint(min_ifg, 2 * min_ifg)

                if debug_fill:
                    print "filled {} {} {} {}".format(packet.inter_frame_gap, packet_time, gap_size, packet_type)
                
        return (last_packet_end, ifg)


def do_test(mac, tx_clk, tx_phy, seed,
            num_windows=10, num_avb_streams=12, num_avb_data_bytes=400,
            weight_none=50, weight_lp=50, weight_other=50,
            data_len_min=46, data_len_max=500,
            weight_tagged=50, weight_untagged=50):

    rand = random.Random()
    rand.seed(seed)

    bit_time = tx_phy.get_clock().get_bit_time()
    rxLpControl = RxLpControl('tile[0]:XS1_PORT_1D', bit_time, 0, True, rand.randint(0, sys.maxint))

    resources = xmostest.request_resource("xsim")
    testname = 'test_avb_traffic'
    level = 'nightly'

    binary = '{test}/bin/{mac}_{phy}/{test}_{mac}_{phy}.xe'.format(
        test=testname, mac=mac, phy=tx_phy.get_name())

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Running {test}: {phy} phy at {clk} (seed {seed})".format(
            test=testname, phy=tx_phy.get_name(), clk=tx_clk.get_name(), seed=seed)

    stream_mac_addresses = {}
    stream_seq_id = {}
    stream_ids = [x for x in range(num_avb_streams)]
    for i in stream_ids:
        stream_mac_addresses[i] = [i, 1, 2, 3, 4, 5]
        stream_seq_id[i] = 0
        
    packets = []
    filler = PacketFiller(weight_none, weight_lp, weight_other, weight_tagged, weight_untagged,
                          data_len_min, data_len_max, bit_time)

    window_size = 125000
    
    min_ifg = 96 * bit_time
    last_packet_end = 0
    ifg = 0
    for window in range(num_windows):
        # Randomly place the streams in the 125us window
        packet_start_times = sorted([rand.randint(0, window_size) for x in range(num_avb_streams)])

        if debug_fill:
            print "Window {} - times {}".format(window, packet_start_times)

        rand.shuffle(stream_ids)
        for (i, stream) in enumerate(stream_ids):
            packet_start_time = packet_start_times[i]

            gap_size = packet_start_time - last_packet_end

            (last_packet_end, ifg) = filler.fill_gap(rand, packets, gap_size, last_packet_end, ifg)
            start_ifg = min_ifg

            avb_packet= MiiPacket(rand,
                dst_mac_addr=stream_mac_addresses[stream],
                create_data_args=['same', (stream_seq_id[stream], num_avb_data_bytes)],
                vlan_prio_tag=[0x81, 0x00, 0x00, 0x00],
                inter_frame_gap=ifg)
            stream_seq_id[stream] += 1
            packets.append(avb_packet)
            ifg = rand.randint(min_ifg, 2 * min_ifg)

            packet_time = avb_packet.get_packet_time(bit_time)

            if debug_fill:
                print "PACKET {} -> {}".format(last_packet_end, last_packet_end + packet_time)
            last_packet_end += packet_time

        # Fill the window after the last packet
        gap_size = window_size - last_packet_end
        (last_packet_end, ifg) = filler.fill_gap(rand, packets, gap_size, last_packet_end, ifg)

        # Compute where in the next window the last packet has finished
        last_packet_end = last_packet_end - window_size
        
    tx_phy.set_packets(packets)

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), level):
        print "Running {w} windows of {s} AVB streams with {b} data bytes each".format(
            w=num_windows, s=num_avb_streams, b=num_avb_data_bytes)
        print "Sending {n} lp packets with {b} bytes hp data".format(
            n=filler.lp_seq_id, b=filler.lp_data_bytes)
        print "Sending {n} other packets with {b} bytes hp data".format(
            n=filler.other_seq_id, b=filler.other_data_bytes)

    expect_folder = create_if_needed("expect")
    expect_filename = '{folder}/{test}_{mac}_{phy}.expect'.format(
        folder=expect_folder, test=testname, mac=mac, phy=tx_phy.get_name())
    create_expect(packets, expect_filename, num_windows, num_avb_streams, num_avb_data_bytes)
    tester = xmostest.ComparisonTester(open(expect_filename),
                                     'lib_ethernet', 'basic_tests', testname,
                                      {'mac':mac, 'phy':tx_phy.get_name(), 'clk':tx_clk.get_name(),
                                       'n_stream':num_avb_streams, 'b_p_stream':num_avb_data_bytes,
                                       'len_min':data_len_min, 'len_max':data_len_max,
                                       'w_none':weight_none, 'w_lp':weight_lp, 'w_other':weight_other,
                                       'n_windows':num_windows},
                                      regexp=True)

    tester.set_min_testlevel(level)

    simargs = get_sim_args(testname, mac, tx_clk, tx_phy)
    xmostest.run_on_simulator(resources['xsim'], binary,
                              simthreads=[tx_clk, tx_phy, rxLpControl],
                              tester=tester,
                              simargs=simargs)

def create_expect(packets, filename, num_windows, num_streams, num_data_bytes):
    """ Create the expect file for what packets should be reported by the DUT
    """
    # Each stream will receive one packet in each window. That packet is VLAN tagged
    # so the header overhead is 18 bytes
    stream_bytes = num_windows * (num_data_bytes + 18)
    with open(filename, 'w') as f:
        for i in range(num_streams):
            f.write("Stream {} received {} packets, {} bytes\n".format(
                i, num_windows, stream_bytes))
        f.write("Received \d+ lp bytes\n")

def runtest():

    if args.data_len_max < args.data_len_min:
        print "ERROR: Invalid arguments, data_len_max ({max}) cannot be less than data_len_min ({min})".format(
            min=args.data_len_min, max=args.data_len_max)
        return

    random.seed(1)

    # Test 100 MBit - MII
    (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(test_ctrl='tile[0]:XS1_PORT_1C', expect_loopback=False,
                                             dut_exit_time=100000, verbose=args.verbose)
    if run_on(phy='mii', clk='25Mhz', mac='rt'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        do_test('rt', tx_clk_25, tx_mii, seed, num_avb_streams=2, num_avb_data_bytes=200)

    # Test 1GBit - RGMII
    (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, test_ctrl='tile[0]:XS1_PORT_1C',
                                                  expect_loopback=False, dut_exit_time=200000,
                                                  verbose=args.verbose)
    if run_on(phy='rgmii', clk='125Mhz', mac='rt'):
        seed = args.seed if args.seed else random.randint(0, sys.maxint)
        do_test('rt', tx_clk_125, tx_rgmii, seed, num_avb_streams=12)
