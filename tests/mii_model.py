import xmostest
import sys
import zlib

class Clock(xmostest.SimThread):

    def __init__(self, port, rate):
        self._period = float(1000000000) / rate
        self._val = 0
        self._port = port

    def run(self):
        while True:
            self.wait_until(self.xsi.get_time() + self._period)
            self._val = 1 - self._val
            self.xsi.drive_port_pins(self._port, self._val)

    def is_high(self):
        return (self._val == 1)

    def is_low(self):
        return (self._val == 0)

class MiiTransmitter(xmostest.SimThread):

    def __init__(self, rxd, rxdv, clock, packets, initial_delay = 30000,
                 verbose = False):
        self._rxd = rxd
        self._rxdv = rxdv
        self._packets = packets
        self._clock = clock
        self._initial_delay = initial_delay
        self._interframe_gap = 960
        self._verbose = verbose

    def run(self):
        xsi = self.xsi
        self.wait_until(xsi.get_time() + self._initial_delay)
        i = 1
        for packet in self._packets:
            if self._verbose:
                print "Sending packet %d, len = %d." % (i, len(packet))
            i += 1

            # Start with preamble
            nibbles = [0x5 for x in range(7)]
            nibbles.append(0xD)

            # Then the data
            for byte in packet:
                nibbles.append(byte & 0xf)
                nibbles.append((byte>>4) & 0xf)

            # Finally the CRC
            data = ''.join(chr(x) for x in packet)
            crc = zlib.crc32(data)&0xFFFFFFFF
            nibbles.append((crc >>  0) & 0xf)
            nibbles.append((crc >>  4) & 0xf)
            nibbles.append((crc >>  8) & 0xf)
            nibbles.append((crc >> 12) & 0xf)
            nibbles.append((crc >> 16) & 0xf)
            nibbles.append((crc >> 20) & 0xf)
            nibbles.append((crc >> 24) & 0xf)
            nibbles.append((crc >> 28) & 0xf)

            self.wait(lambda x: self._clock.is_high())
            self.wait(lambda x: self._clock.is_low())
            xsi.drive_port_pins(self._rxdv, 1)
            for nibble in nibbles:
                self.wait(lambda x: self._clock.is_low())
                xsi.drive_port_pins(self._rxd, nibble)
                self.wait(lambda x: self._clock.is_high())
            self.wait(lambda x: self._clock.is_low())
            xsi.drive_port_pins(self._rxdv, 0)
            self.wait_until(xsi.get_time() + self._interframe_gap)
            if self._verbose:
                print "Sent"



class MiiReceiver(xmostest.SimThread):

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
        while True:
            # Wait for TXEN to go high
            self.wait_for_port_pins_change([self._txen])
            packet = []
            nibble_index = 0
            byte = 0
            in_preamble = True
            while True:
                # Wait for a falling clock edge or enable low
                self.wait(lambda x: self._clock.is_low() or \
                                   xsi.sample_port_pins(self._txen) == 0)
                if xsi.sample_port_pins(self._txen) == 0:
                    break
                nibble = xsi.sample_port_pins(self._txd)
                if in_preamble:
                    if nibble == 0xd:
                        in_preamble = False
                    elif nibble != 0x5:
                        print "ERROR: Invalid preamble value: %x" % nibble
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

