import xmostest
import sys
import zlib

class RgmiiPhy(xmostest.SimThread):

    def __init__(self):
        self._name = 'rgmii'

    def get_name(self):
        return self._name

        
class RgmiiTransmitter(RgmiiPhy):

    (FULL_DUPLEX, HALF_DUPLEX) = (0x8, 0x0)
    (LINK_UP, LINK_DOWN) = (0x1, 0x0)

    def __init__(self, test_ctrl, rxd, rxdv, clock, packets,
                 initial_delay=30000, verbose=False):
        super(RgmiiTransmitter, self).__init__()
        self._test_ctrl = test_ctrl
        self._rxd = rxd
        self._rxdv = rxdv
        self._packets = []
        self._clock = clock
        self._initial_delay = initial_delay
        self._verbose = verbose
        self._phy_status = self.FULL_DUPLEX | self.LINK_UP | clock.get_rate()

    def run(self):
        xsi = self.xsi

        # When DV is low, the PHY should indicate its mode on the DATA pins
        xsi.drive_port_pins(self._rxd, self._phy_status)
        
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

            # When DV is low, the PHY should indicate its mode on the DATA pins
            xsi.drive_port_pins(self._rxd, self._phy_status)

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



class RgmiiReceiver(RgmiiPhy):

    def __init__(self, txd, txen, clock, print_packets = False,
                 packet_fn = None, terminate_after = -1):
        self._txd = txd
        self._txen = txen
        self._clock = clock
        self._print_packets = print_packets
        self._terminate_after = terminate_after
        self._packet_fn = packet_fn

    def run(self):
        xsi = self.xsi
        self.wait_for_port_pins_change([self._txen])

        packet_count = 0
        last_frame_end_time = None
        while True:
            # Wait for TXEN to go high
            self.wait_for_port_pins_change([self._txen])
            packet = []
            frame_start_time = self.xsi.get_time()
            nibble_index = 0
            byte = 0
            in_preamble = True
            preamble_0x5_count = 0

            if last_frame_end_time:
                ifgap = frame_start_time - last_frame_end_time
                # UNH-IOL MAC Test 4.2.2
                if (ifgap < 960):
                    print "ERROR: Invalid interframe gap of %d ns" % ifgap

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
                        # UNH-IOL MAC Test 4.2.1
                        if preamble_0x5_count != 15:
                            print "ERROR: Invalid number of 0x5 preamble nibbles: %d" % preamble_0x5_count
                        in_preamble = False
                    elif nibble != 0x5:
                        print "ERROR: Invalid preamble value: %x" % nibble
                    else:
                        preamble_0x5_count += 1
                elif (nibble_index == 0):
                    byte = nibble
                    nibble_index = 1
                else:
                    byte = byte + (nibble << 4)
                    packet.append(byte)
                    nibble_index = 0

                self.wait(lambda x: self._clock.is_high())

            # End of packet
            packet_crc = packet[-4] + (packet[-3] << 8) + \
                         (packet[-2] << 16) + (packet[-1] << 24)
            data = ''.join(chr(x) for x in packet[:-4])
            expected_crc = zlib.crc32(data)&0xFFFFFFFF
            # UNH-IOL MAC Test 4.2.3
            if packet_crc != expected_crc:
                print "ERROR: Invalid crc (got 0x%x, expecting 0x%x)" % (packet_crc, expected_crc)
            if self._print_packets:
                print "Packet received, len=%d." % (len(packet) - 4)
                for x in packet:
                    sys.stdout.write("0x%x,"%x)
                sys.stdout.write("\n")
            if self._packet_fn:
                self._packet_fn(packet[:-4])

            packet_count += 1
            if packet_count == self._terminate_after:
                xsi.terminate()

