import random
import xmostest
import sys
import zlib
from itertools import izip
from mii_phy import TxPhy, RxPhy
from mii_packet import MiiPacket
from mii_clock import Clock

def pairwise(t):
    it = iter(t)
    return izip(it,it)


class RgmiiTransmitter(TxPhy):

    (FULL_DUPLEX, HALF_DUPLEX) = (0x8, 0x0)
    (LINK_UP, LINK_DOWN) = (0x1, 0x0)

    def __init__(self, rxd, rxd_100, rxdv, mode_rxd, mode_rxdv, rxer, clock,
                 initial_delay=130000, verbose=False, test_ctrl=None,
                 do_timeout=True, complete_fn=None, expect_loopback=True,
                 dut_exit_time=25000):
        super(RgmiiTransmitter, self).__init__('rgmii', rxd, rxdv, rxer, clock,
                                               initial_delay, verbose, test_ctrl,
                                               do_timeout, complete_fn, expect_loopback,
                                               dut_exit_time)
        self._mode_rxd = mode_rxd
        self._rxd_100 = rxd_100
        self._mode_rxdv = mode_rxdv
        self._phy_status = (self.FULL_DUPLEX | self.LINK_UP | clock.get_rate())

        # Create the byte-wide version of the data
        self._phy_status = (self._phy_status << 4) | self._phy_status

    def set_dv(self, value):
        self.xsi.drive_port_pins(self._rxdv, value)
        self.xsi.drive_port_pins(self._mode_rxdv, value)

    def set_data(self, value):
        self.xsi.drive_port_pins(self._rxd, value)
        self.xsi.drive_port_pins(self._rxd_100, value)
        self.xsi.drive_port_pins(self._mode_rxd, value)

    def run(self):
        xsi = self.xsi

        # When DV is low, the PHY should indicate its mode on the DATA pins
        self.set_data(self._phy_status)

        self.start_test()

        for i,packet in enumerate(self._packets):
            packet_rate = self._clock.get_rate()

            error_nibbles = packet.get_error_nibbles()

            self.wait_until(xsi.get_time() + packet.inter_frame_gap)

            if self._verbose:
                print "Sending packet {i}: {p}".format(i=i, p=packet)
                sys.stdout.write(packet.dump())

            if packet_rate == Clock.CLK_125MHz:
                # The RGMII phy puts a nibble on each edge at 1Gb/s. This is mapped
                # to having a byte every clock by the shim in the DUT
                i = 0
                for (a,b) in pairwise(packet.get_nibbles()):
                    byte = a | (b << 4)
                    self.wait(lambda x: self._clock.is_low())
                    self.set_dv(1)
                    self.set_data(byte)

                    # Signal an error if required
                    if i in error_nibbles or i+1 in error_nibbles:
                        xsi.drive_port_pins(self._rxer, 1)
                    else:
                        xsi.drive_port_pins(self._rxer, 0)

                    self.wait(lambda x: self._clock.is_high())
                    i += 2
            else:
                # The RGMII phy will replicate the data on both edges at 10/100Mb/s
                for (i, nibble) in enumerate(packet.get_nibbles()):
                    byte = nibble | (nibble << 4)
                    self.wait(lambda x: self._clock.is_low())
                    self.set_dv(1)
                    self.set_data(byte)

                    # Signal an error if required
                    if i in error_nibbles:
                        xsi.drive_port_pins(self._rxer, 1)
                    else:
                        xsi.drive_port_pins(self._rxer, 0)

                    self.wait(lambda x: self._clock.is_high())

            self.wait(lambda x: self._clock.is_low())

            # When DV is low, the PHY should indicate its mode on the DATA pins
            self.set_data(self._phy_status)
            self.set_dv(0)
            xsi.drive_port_pins(self._rxer, 0)

            if self._verbose:
                print "Sent"

        self.end_test()


class RgmiiReceiver(RxPhy):

    def __init__(self, txd, txen, clock, print_packets=False,
                 packet_fn=None, verbose=None, test_ctrl=None):
        super(RgmiiReceiver, self).__init__('rgmii', txd, txen, clock, print_packets,
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

                if xsi.sample_port_pins(self._txen) == 0 and xsi.sample_port_pins(self._test_ctrl) == 1:
                    xsi.terminate()

            # Start with a blank packet to ensure they are filled in by the receiver
            packet = MiiPacket(rand, blank=True)

            frame_start_time = self.xsi.get_time()
            in_preamble = True
            packet_rate = self._clock.get_rate()

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

                if packet_rate == Clock.CLK_125MHz:
                    # The RGMII phy at 1Gb/s expects a different nibble on each clock edge
                    # and hence will get a byte per cycle
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
                else:
                    # The RGMII phy at 10/100Mb/s only gets one nibble of data per clock
                    nibble = byte & 0xf
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
