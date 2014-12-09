import xmostest
import sys
import zlib
from itertools import izip
from mii_phy import TxPhy, RxPhy

def pairwise(t):
    it = iter(t)
    return izip(it,it)


class RgmiiTransmitter(TxPhy):

    (FULL_DUPLEX, HALF_DUPLEX) = (0x8, 0x0)
    (LINK_UP, LINK_DOWN) = (0x1, 0x0)

    def __init__(self, rxd, rxdv, mode_rxd, mode_rxdv, clock,
                 initial_delay=30000, verbose=False, test_ctrl=None):
        super(RgmiiTransmitter, self).__init__('rgmii', rxd, rxdv, clock, initial_delay, verbose, test_ctrl)
        self._mode_rxd = mode_rxd
        self._mode_rxdv = mode_rxdv
        self._phy_status = (self.FULL_DUPLEX | self.LINK_UP | clock.get_rate())

        # Create the byte-wide version of the data
        self._phy_status = (self._phy_status << 4) | self._phy_status

    def set_dv(self, value):
        self.xsi.drive_port_pins(self._rxdv, value)
        self.xsi.drive_port_pins(self._mode_rxdv, value)

    def set_data(self, value):
        self.xsi.drive_port_pins(self._rxd, value)
        self.xsi.drive_port_pins(self._mode_rxd, value)

    def run(self):
        xsi = self.xsi

        # When DV is low, the PHY should indicate its mode on the DATA pins
        self.set_data(self._phy_status)

        self.start_test()

        for i,packet in enumerate(self._packets):
            if self._verbose:
                print "Sending packet {p}".format(p=packet)
                packet.dump()

            # Don't wait the inter-frame gap on the first packet
            if i:
                self.wait_until(xsi.get_time() + packet.inter_frame_gap)

            for (a,b) in pairwise(packet.get_nibbles()):
                byte = (a << 4) | b
                self.wait(lambda x: self._clock.is_low())
                self.set_dv(1)
                self.set_data(byte)
                self.wait(lambda x: self._clock.is_high())
            self.wait(lambda x: self._clock.is_low())

            # When DV is low, the PHY should indicate its mode on the DATA pins
            self.set_data(self._phy_status)
            self.set_dv(0)

            if self._verbose:
                print "Sent"

        self.end_test()


class RgmiiReceiver(RxPhy):

    def __init__(self, txd, txen, clock, print_packets=False,
                 packet_fn=None, test_ctrl=None):
        super(RgmiiReceiver, self).__init__('rgmii', txd, txen, clock, print_packets, packet_fn, test_ctrl)

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
                byte = xsi.sample_port_pins(self._txd)
                if in_preamble:
                    if byte == 0xd5:
                        packet.append_preamble_nibble(byte & 0xf)
                        packet.set_sfd_nibble(byte >> 4)
                        in_preamble = False
                    else:
                        packet.append_preamble_nibble(byte & 0xf)
                        packet.append_preamble_nibble(byte >> 4)
                else:
                    packet.append_data_byte(byte)

                self.wait(lambda x: self._clock.is_high())

            packet.complete()

            if self._print_packets:
                packet.dump()

            if self._packet_fn:
                self._packet_fn(packet, self)

            # Perform packet checks
            packet.check(self._clock)
