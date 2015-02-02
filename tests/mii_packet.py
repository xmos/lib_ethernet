
import sys
import zlib
import random


# Functions for creating the data contents of packets
def create_data(args):
    f_name,f_args = args
    func = 'create_data_{}'.format(f_name)
    return globals()[func](f_args)

def create_data_step(args):
    step,num_data_bytes = args
    return [(step * i) & 0xff for i in range(num_data_bytes)]

def create_data_same(args):
    value,num_data_bytes = args
    return [value & 0xff for i in range(num_data_bytes)]


# Functions for creating the expected output that the DUT will print given
# this packet
def create_data_expect(args):
    f_name,f_args = args
    func = 'create_data_expect_{}'.format(f_name)
    return globals()[func](f_args)

def create_data_expect_step(args):
    step,num_data_bytes = args
    return "Step = {0}\n".format(step)

def create_data_expect_same(args):
    value,num_data_bytes = args
    return "Value = {0}\n".format(value)


class MiiPacket(object):
    """ The MiiPacket class contains all the data to represent a packet on the wire.
        This includes the inter-frame gap (IFG), preamble and CRC.

        The packet structure is able to represent both valid and invalid packets
        for the purpose of testing.

    """

    # The maximum payload value (1500 bytes)
    MAX_ETHER_LEN = 0x5dc

    def __init__(self, rand, **kwargs):
        blank = kwargs.pop('blank', False)

        self.dropped = False

        if blank:
            self.num_preamble_nibbles = 0
            self.sfd_nibble = 0
            self.num_data_bytes = 0
            self.inter_frame_gap = 0.0
            self.dst_mac_addr = []
            self.src_mac_addr = []
            self.vlan_prio_tag = []
            self.ether_len_type = []
            self.data_bytes = []
        else:
            self.num_preamble_nibbles = 15
            self.sfd_nibble = 0xd
            self.num_data_bytes = 46
            self.inter_frame_gap = 960
            self.dst_mac_addr = None
            self.src_mac_addr = None
            self.vlan_prio_tag = None
            self.ether_len_type = None
            self.data_bytes = None

        self.preamble_nibbles = None
        self.send_crc_word = True
        self.corrupt_crc = False
        self.extra_nibble = False
        self.seed = None
        self.create_data_args = None
        self.send_header = True
        self.nibble = None
        self.packet_crc = 0
        self.error_nibbles = []

        # Get all other values from the dictionary passed in
        for arg,value in kwargs.iteritems():
            setattr(self, arg, value)

        # Preamble nibbles - define valid preamble by default
        if self.preamble_nibbles is None:
            self.preamble_nibbles = [0x5 for x in range(self.num_preamble_nibbles)]

        # Destination MAC address - use a random one if not user-defined
        if self.dst_mac_addr is None:
            self.dst_mac_addr = [rand.randint(0, 255) for x in range(6)]

        # Source MAC address - use a random one if not user-defined
        if self.src_mac_addr is None:
            self.src_mac_addr = [rand.randint(0, 255) for x in range(6)]

        # If the data is defined, then record the length. Otherwise create random
        # data of the length specified
        if self.data_bytes is None and not blank:
            if self.create_data_args:
                self.data_bytes = create_data(self.create_data_args)
            else:
                self.data_bytes = [rand.randint(0, 255) for x in range(self.num_data_bytes)]

        # Ensure that however the data has been created, the length is correct
        if self.data_bytes is None:
            self.num_data_bytes = 0
        else:
            self.num_data_bytes = len(self.data_bytes)

        # If the ether length/type field is not specified then set it to something sensible
        if self.ether_len_type is None:
            if self.ether_len_type <= self.MAX_ETHER_LEN:
                self.ether_len_type = [ (self.num_data_bytes >> 8) & 0xff, self.num_data_bytes & 0xff ]
            else:
                self.ether_len_type = [ 0x00, 0x00 ]

        # If there is an extra nibble, choose it now
        if self.extra_nibble:
            self.extra_nibble = rand.randint(0, 15)

    def get_ifg(self):
        return self.inter_frame_gap

    def set_ifg(self, inter_frame_gap):
        self.inter_frame_gap = inter_frame_gap

    def get_packet_bytes(self):
        """ Returns all the data bytes of the packet. This does not include preamble or CRC
        """
        packet_bytes = []
        if self.vlan_prio_tag:
            packet_bytes = self.dst_mac_addr + self.src_mac_addr + self.vlan_prio_tag + \
                                         self.ether_len_type + self.data_bytes
        else:
            packet_bytes = self.dst_mac_addr + self.src_mac_addr + \
                                         self.ether_len_type + self.data_bytes
        return packet_bytes

    def get_crc(self, packet_bytes):
        # Finally the CRC
        data = ''.join(chr(x) for x in packet_bytes)
        crc = zlib.crc32(data) & 0xFFFFFFFF
        if self.corrupt_crc:
            crc = ~crc
        return crc

    def get_packet_time(self, bit_time):
        data_time = len(self.get_nibbles()) * 4 * bit_time
        return data_time + self.inter_frame_gap

    def get_nibbles(self):
        nibbles = []

        for nibble in self.preamble_nibbles:
            nibbles.append(nibble)

        if self.sfd_nibble is not None:
            nibbles.append(self.sfd_nibble)

        packet_bytes = self.get_packet_bytes()
        for byte in packet_bytes:
            nibbles.append(byte & 0xf)
            nibbles.append((byte>>4) & 0xf)

        if self.send_crc_word:
            crc = self.get_crc(packet_bytes)
            for i in range(0, 8):
                nibbles.append((crc >> (4*i)) & 0xf)

        # Add an extra random nibble for alignment test
        if self.extra_nibble:
            nibbles.append(self.extra_nibble)

        return nibbles

    def append_preamble_nibble(self, nibble):
        if self.preamble_nibbles is None:
            self.preamble_nibbles = []
        self.preamble_nibbles.append(nibble)
        self.num_preamble_nibbles = len(self.preamble_nibbles)

    def set_sfd_nibble(self, nibble):
        self.sfd_nibble = nibble

    def append_data_nibble(self, nibble):
        """ Add a nibble to a packet. Manage merging nibbles into bytes and
            then place it in the correct place in the packet structure.
        """
        if self.nibble is None:
            self.nibble = nibble
            return

        byte = self.nibble | nibble << 4
        self.nibble = None

        self.append_data_byte(byte)

    def append_data_byte(self, byte):
        if len(self.dst_mac_addr) < 6:
            self.dst_mac_addr.append(byte)
            return

        if len(self.src_mac_addr) < 6:
            self.src_mac_addr.append(byte)
            return

        if len(self.vlan_prio_tag) >= 2 and len(self.vlan_prio_tag) < 4:
            self.vlan_prio_tag.append(byte)
            return

        if len(self.ether_len_type) < 2:
            self.ether_len_type.append(byte)

            # Detect the fact that this is actually a VLAN/Priority tag
            if (len(self.ether_len_type) == 2 and
                    self.ether_len_type[0] == 0x81 and
                    self.ether_len_type[1] == 0x00):
                self.vlan_prio_tag = self.ether_len_type
                self.ether_len_type = []

            return

        self.data_bytes.append(byte)
        self.num_data_bytes += 1

    def complete(self):
        """ When a packet has been fully received then move the CRC from the data
        """
        if len(self.data_bytes) >= 4:
            self.packet_crc = (self.data_bytes[-4] + (self.data_bytes[-3] << 8) +
                              (self.data_bytes[-2] << 16) + (self.data_bytes[-1] << 24))
        else:
            self.packet_crc = 0
        self.data_bytes = self.data_bytes[:-4]
        self.num_data_bytes -= 4

    def get_error_nibbles(self):
        return self.error_nibbles

    def check(self, clock):
        """ Check the packet contents - valid preamble, IFG, length, CRC.
        """

        # UNH-IOL MAC Test 4.2.2 (only check if it is non-zero as otherwise it is simply the first packet)
        if self.inter_frame_gap and (self.inter_frame_gap < clock.get_min_ifg()):
            print "ERROR: Invalid interframe gap of {0} ns".format(self.inter_frame_gap)

        # UNH-IOL MAC Test 4.2.1
        if self.num_preamble_nibbles != 15:
            print "ERROR: Invalid number of 0x5 preamble nibbles: {0}".format(self.num_preamble_nibbles)

        if self.sfd_nibble != 0xd:
            print "ERROR: Invalid SFD nibble: {0:#x}".format(self.sfd_nibble)

        for nibble in self.preamble_nibbles:
            if nibble != 0x5:
                print "ERROR: Invalid preamble value: {0:#x}".format(nibble)

        if self.nibble is not None:
            print "ERROR: Odd number of data nibbles received"

        # Ensure that if the len/type field specifies a length then it is valid (Section 3.2.6 of 802.3-2012)
        if len(self.ether_len_type) != 2:
            print "ERROR: The len/type field contains {0} bytes".format(len(self.ether_len_type))
        else:
            len_type = self.ether_len_type[0] << 8 | self.ether_len_type[1]
            if len_type <= 1500:
                if len_type > self.num_data_bytes:
                    print "ERROR: len/type field value ({0}) != packet bytes ({1})".format(
                        len_type, self.num_data_bytes)

        # Check the CRC
        data = ''.join(chr(x) for x in self.get_packet_bytes())
        expected_crc = zlib.crc32(data) & 0xFFFFFFFF

        # UNH-IOL MAC Test 4.2.3
        if self.packet_crc != expected_crc:
            print "ERROR: Invalid crc (got {got}, expecting {expect})".format(
                got=self.packet_crc, expect=expected_crc)

    def dump(self, show_ifg=True):
        output = ""
        # Discount the CRC word from the bytes received
        output += "Packet len={len}, dst=[{dst}], src=[{src}]".format(
            len=self.num_data_bytes,
            dst=" ".join(["0x{0:0>2x}".format(i) for i in self.dst_mac_addr]),
            src=" ".join(["0x{0:0>2x}".format(i) for i in self.src_mac_addr]))

        if self.vlan_prio_tag:
            output += ", vlan/prio=[{vp}]".format(
                vp=" ".join(["0x{0:0>2x}".format(i) for i in self.vlan_prio_tag]))

        output += ", len/type=[{lt}]".format(
            lt=" ".join(["0x{0:0>2x}".format(i) for i in self.ether_len_type]))
        output += "\n"

        output += "data=[\n    "
        for i,x in enumerate(self.data_bytes):
            if i and ((i%16) == 0):
                output += "\n    "
            output += "0x{0:0>2x}, ".format(x)
        output += "\n]\n"
        if self.send_crc_word:
            crc = self.get_crc(self.get_packet_bytes())
            output += "CRC: 0x{0:0>8x}".format(crc & 0xffffffff)
            if show_ifg:
                output += ", IFG: {i}\n".format(i=self.inter_frame_gap)
            else:
                output += "\n"

        return output

    def get_data_expect(self):
        """ Return the expected DUT print for the given data contents
        """
        if (self.create_data_args):
            return create_data_expect(self.create_data_args)
        else:
            return ""

    def __str__(self):
        return "{0} preamble nibbles, {1} data bytes".format(
            self.num_preamble_nibbles, len(self.data_bytes))

    def __ne__(self, other):
        return not self.__eq__(other)

    def __eq__(self, other):
        if (self.dst_mac_addr != other.dst_mac_addr or
                self.src_mac_addr != other.src_mac_addr or
                self.ether_len_type != other.ether_len_type or
                self.data_bytes != other.data_bytes):
            return False

        # The VLAN/Prio field can either be None or have length 0. Only check
        # they are the same if one is set
        if ((self.vlan_prio_tag is not None and len(self.vlan_prio_tag) > 0) or
                (other.vlan_prio_tag is not None and len(other.vlan_prio_tag) > 0)):
            if self.vlan_prio_tag != other.vlan_prio_tag:
                return false

        return True
