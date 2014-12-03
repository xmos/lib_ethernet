import xmostest
import sys
import zlib

from mii_packet import MiiPacket

class MiiPhy(xmostest.SimThread):

    def __init__(self):
        super(MiiPhy, self).__init__()
        self._name = 'mii'

    def get_name(self):
        return self._name


class MiiTransmitter(MiiPhy):

    # Time in ns from the last packet being sent until the end of test is signalled to the DUT
    END_OF_TEST_TIME = 5000

    def __init__(self, test_ctrl, rxd, rxdv, clock,
                 initial_delay=30000, verbose=False):
        super(MiiTransmitter, self).__init__()
        self._test_ctrl = test_ctrl
        self._rxd = rxd
        self._rxdv = rxdv
        self._packets = []
        self._clock = clock
        self._initial_delay = initial_delay
        self._verbose = verbose

    def run(self):
        xsi = self.xsi
        self.wait_until(xsi.get_time() + self._initial_delay)
        self.wait(lambda x: self._clock.is_high())
        self.wait(lambda x: self._clock.is_low())

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

        if self._verbose:
            print "All packets sent"

        # Give the DUT a reasonable time to process the packet
        self.wait_until(xsi.get_time() + self.END_OF_TEST_TIME)

        # Indicate to the DUT that the test has finished
        xsi.drive_port_pins(self._test_ctrl, 1)

    def set_clock(self, clock):
        self._clock = clock

    def set_packets(self, packets):
        self._packets = packets



class MiiReceiver(MiiPhy):

    def __init__(self, test_ctrl, txd, txen, clock, print_packets = False,
                 packet_fn = None):
        self._txd = txd
        self._txen = txen
        self._clock = clock
        self._print_packets = print_packets
        self._test_ctrl = test_ctrl
        self._packet_fn = packet_fn

    def run(self):
        xsi = self.xsi
        self.wait_for_port_pins_change([self._txen])

        packet_count = 0
        last_frame_end_time = None
        while True:
            if xsi.sample_port_pins(self._test_ctrl) == 1:
                xsi.terminate()

            # Wait for TXEN to go high
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

            if self._print_packets:
                packet.dump()

            if self._packet_fn:
                self._packet_fn(packet)

            # Perform packet checks
            packet.check(self._clock)
