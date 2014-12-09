import xmostest
import sys
import zlib

from mii_packet import MiiPacket

class TxPhy(xmostest.SimThread):

    # Time in ns from the last packet being sent until the end of test is signalled to the DUT
    END_OF_TEST_TIME = 5000

    def __init__(self, name, rxd, rxdv, clock, initial_delay, verbose, test_ctrl):
        self._name = name
        self._test_ctrl = test_ctrl
        self._rxd = rxd
        self._rxdv = rxdv
        self._packets = []
        self._clock = clock
        self._initial_delay = initial_delay
        self._verbose = verbose

    def get_name(self):
        return self._name

    def get_clock(self):
        return self._clock

    def start_test(self):
        self.wait_until(self.xsi.get_time() + self._initial_delay)
        self.wait(lambda x: self._clock.is_high())
        self.wait(lambda x: self._clock.is_low())

    def end_test(self):
        if self._verbose:
            print "All packets sent"

        # Give the DUT a reasonable time to process the packet
        self.wait_until(self.xsi.get_time() + self.END_OF_TEST_TIME)

        if self._test_ctrl:
            # Indicate to the DUT that the test has finished
            self.xsi.drive_port_pins(self._test_ctrl, 1)

        # Allow time for a maximum sized packet to arrive
        timeout_time = (self._clock.get_bit_time() * 1522 * 8)
        # And allow some time for the packets to get through the buffers internally
        #  - packet is copied twice at a rate of 1-bit per cycle
        timeout_time += 2 * 1522 * 8
        # Add some overhead for the system
        timeout_time += 10000
        self.wait_until(self.xsi.get_time() + timeout_time)
        print "ERROR: Test timed out"
        self.xsi.terminate()

    def set_clock(self, clock):
        self._clock = clock

    def set_packets(self, packets):
        self._packets = packets


class MiiTransmitter(TxPhy):

    def __init__(self, rxd, rxdv, clock,
                 initial_delay=30000, verbose=False, test_ctrl=None):
        super(MiiTransmitter, self).__init__('mii', rxd, rxdv, clock, initial_delay, verbose, test_ctrl)

    def run(self):
        xsi = self.xsi

        self.start_test()

        for i,packet in enumerate(self._packets):
            if self._verbose:
                print "Sending packet {p}".format(p=packet)
                packet.dump()

            # Don't wait the inter-frame gap on the first packet
            if i:
                self.wait_until(xsi.get_time() + packet.inter_frame_gap)

            for nibble in packet.get_nibbles():
                self.wait(lambda x: self._clock.is_low())
                xsi.drive_port_pins(self._rxdv, 1)
                xsi.drive_port_pins(self._rxd, nibble)
                self.wait(lambda x: self._clock.is_high())
            self.wait(lambda x: self._clock.is_low())
            xsi.drive_port_pins(self._rxdv, 0)

            if self._verbose:
                print "Sent"

        self.end_test()


class RxPhy(xmostest.SimThread):

    def __init__(self, name, txd, txen, clock, print_packets, packet_fn, test_ctrl):
        self._name = name
        self._txd = txd
        self._txen = txen
        self._clock = clock
        self._print_packets = print_packets
        self._test_ctrl = test_ctrl
        self._packet_fn = packet_fn

        self.expected_packets = None
        self.expect_packet_index = 0
        self.num_expected_packets = 0

        self.expected_packets = None
        self.expect_packet_index = 0
        self.num_expected_packets = 0

    def get_name(self):
        return self._name

    def get_clock(self):
        return self._clock

    def set_expected_packets(self, packets):
        self.expect_packet_index = 0;
        self.expected_packets = packets
        if self.expected_packets is None:
            self.num_expected_packets = 0
        else:
            self.num_expected_packets = len(self.expected_packets)

class MiiReceiver(RxPhy):

    def __init__(self, txd, txen, clock, print_packets=False,
                 packet_fn=None, test_ctrl=None):
        super(MiiReceiver, self).__init__('mii', txd, txen, clock, print_packets, packet_fn, test_ctrl)

    def run(self):
        xsi = self.xsi
        self.wait_for_port_pins_change([self._txen])

        packet_count = 0
        last_frame_end_time = None
        while True:
            # Wait for TXEN to go high
            if self._test_ctrl is None:
                self.wait_for_port_pins_change([self._txen])
            else:
                if xsi.sample_port_pins(self._test_ctrl) == 1:
                    xsi.terminate()
                self.wait_for_port_pins_change([self._txen, self._test_ctrl])
                if xsi.sample_port_pins(self._test_ctrl) == 1:
                    xsi.terminate()

            # Start with a blank packet to ensure they are filled in by the receiver
            packet = MiiPacket(blank=True)

            frame_start_time = self.xsi.get_time()
            in_preamble = True

            if last_frame_end_time:
                ifgap = frame_start_time - last_frame_end_time
                packet.inter_frame_gap = ifgap

            while True:
                # Wait for a falling clock edge or enable low
                self.wait(lambda x: self._clock.is_low() or \
                                   xsi.sample_port_pins(self._txen) == 0)

                if xsi.sample_port_pins(self._txen) == 0:
                    last_frame_end_time = self.xsi.get_time()
                    break
                nibble = xsi.sample_port_pins(self._txd)
                if in_preamble:
                    if nibble == 0xd:
                        packet.set_sfd_nibble(nibble)
                        in_preamble = False
                    else:
                        packet.append_preamble_nibble(nibble)
                else:
                    packet.append_data_nibble(nibble)

                self.wait(lambda x: self._clock.is_high())

            packet.complete()

            if self._print_packets:
                packet.dump()

            if self._packet_fn:
                self._packet_fn(packet, self)

            # Perform packet checks
            packet.check(self._clock)


