import random
import xmostest
import sys
import zlib
from mii_packet import MiiPacket

class TxPhy(xmostest.SimThread):

    # Time in ns from the last packet being sent until the end of test is signalled to the DUT
    END_OF_TEST_TIME = 5000

    def __init__(self, name, rxd, rxdv, rxer, clock, initial_delay, verbose,
                 test_ctrl, do_timeout, complete_fn, expect_loopback, dut_exit_time):
        self._name = name
        self._test_ctrl = test_ctrl
        self._rxd = rxd
        self._rxdv = rxdv
        self._rxer = rxer
        self._packets = []
        self._clock = clock
        self._initial_delay = initial_delay
        self._verbose = verbose
        self._do_timeout = do_timeout
        self._complete_fn = complete_fn
        self._expect_loopback = expect_loopback
        self._dut_exit_time = dut_exit_time

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

        if self._complete_fn:
            self._complete_fn(self)

        # Give the DUT a reasonable time to process the packet
        self.wait_until(self.xsi.get_time() + self.END_OF_TEST_TIME)

        if self._do_timeout:
            # Allow time for a maximum sized packet to arrive
            timeout_time = (self._clock.get_bit_time() * 1522 * 8)

            if self._expect_loopback:
                # If looping back then take into account all the data
                total_packet_bytes = sum([len(packet.get_packet_bytes()) for packet in self._packets])

                total_data_bits = total_packet_bytes * 8

                # Allow 2 cycles per bit
                timeout_time += 2 * total_data_bits

                # The clock ticks are 2ns long
                timeout_time *= 2

                # The packets are copied to and from the user application
                timeout_time *= 2

            self.wait_until(self.xsi.get_time() + timeout_time)

            if self._test_ctrl:
                # Indicate to the DUT that the test has finished
                self.xsi.drive_port_pins(self._test_ctrl, 1)

            # Allow time for the DUT to exit
            self.wait_until(self.xsi.get_time() + self._dut_exit_time)

            print "ERROR: Test timed out"
            self.xsi.terminate()

    def set_clock(self, clock):
        self._clock = clock

    def set_packets(self, packets):
        self._packets = packets

    def drive_error(self, value):
        self.xsi.drive_port_pins(self._rxer, value)


class MiiTransmitter(TxPhy):

    def __init__(self, rxd, rxdv, rxer, clock,
                 initial_delay=85000, verbose=False, test_ctrl=None,
                 do_timeout=True, complete_fn=None, expect_loopback=True,
                 dut_exit_time=25000):
        super(MiiTransmitter, self).__init__('mii', rxd, rxdv, rxer, clock,
                                             initial_delay, verbose, test_ctrl,
                                             do_timeout, complete_fn, expect_loopback,
                                             dut_exit_time)

    def run(self):
        xsi = self.xsi

        self.start_test()

        for i,packet in enumerate(self._packets):
            error_nibbles = packet.get_error_nibbles()

            self.wait_until(xsi.get_time() + packet.inter_frame_gap)

            if self._verbose:
                print "Sending packet {i}: {p}".format(i=i, p=packet)
                sys.stdout.write(packet.dump())

            for (i, nibble) in enumerate(packet.get_nibbles()):
                self.wait(lambda x: self._clock.is_low())
                xsi.drive_port_pins(self._rxdv, 1)
                xsi.drive_port_pins(self._rxd, nibble)

                # Signal an error if required
                if i in error_nibbles:
                    xsi.drive_port_pins(self._rxer, 1)
                else:
                    xsi.drive_port_pins(self._rxer, 0)

                self.wait(lambda x: self._clock.is_high())

            self.wait(lambda x: self._clock.is_low())
            xsi.drive_port_pins(self._rxdv, 0)
            xsi.drive_port_pins(self._rxer, 0)

            if self._verbose:
                print "Sent"

        self.end_test()


class RxPhy(xmostest.SimThread):

    def __init__(self, name, txd, txen, clock, print_packets, packet_fn, verbose, test_ctrl):
        self._name = name
        self._txd = txd
        self._txen = txen
        self._clock = clock
        self._print_packets = print_packets
        self._verbose = verbose
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
                 packet_fn=None, verbose=False, test_ctrl=None):
        super(MiiReceiver, self).__init__('mii', txd, txen, clock, print_packets,
                                          packet_fn, verbose, test_ctrl)

    def run(self):
        xsi = self.xsi
        self.wait(lambda x: xsi.sample_port_pins(self._txen) == 0)

        # Need a random number generator for the MiiPacket constructor but it shouldn't
        # have any affect as only blank packets are being created
        rand = random.Random()

        packet_count = 0
        last_frame_end_time = None
        while True:
            # Wait for TXEN to go high
            if self._test_ctrl is None:
                self.wait(lambda x: xsi.sample_port_pins(self._txen) == 1)
            else:
                self.wait(lambda x: xsi.sample_port_pins(self._txen) == 1 or \
                                    xsi.sample_port_pins(self._test_ctrl) == 1)

                if (xsi.sample_port_pins(self._txen) == 0 and
                      xsi.sample_port_pins(self._test_ctrl) == 1):
                    xsi.terminate()

            # Start with a blank packet to ensure they are filled in by the receiver
            packet = MiiPacket(rand, blank=True)

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
                sys.stdout.write(packet.dump())

            if self._packet_fn:
                self._packet_fn(packet, self)

            # Perform packet checks
            packet.check(self._clock)


