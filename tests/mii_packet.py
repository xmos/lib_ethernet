
import sys
import zlib
import numpy
import numpy.random as nprand

def create_data(args):
  f_name,f_args = args
  func = 'create_data_{}'.format(f_name)
  return globals()[func](f_args)

def create_data_step(args):
  step,num_data_bytes = args
  return [(step * i) & 0xff for i in range(num_data_bytes)]

class MiiPacket(object):

  # The maximum payload value (1500 bytes)
  MAX_ETHER_LEN = 0x5dc
  
  def __init__(self, **kwargs):
    blank = kwargs.pop('blank', False)

    if blank:
      self.num_preamble_nibbles = 0
      self.sfd_nibble = 0
      self.num_data_bytes = 0
      self.inter_frame_gap = 0
    else:
      self.num_preamble_nibbles = 15
      self.sfd_nibble = 0xd
      self.num_data_bytes = 46
      self.inter_frame_gap = 960
      
    self.preamble_nibbles = None
    self.send_crc_word = True
    self.data_bytes = None
    self.corrupt_crc = False
    self.extra_nibble = False
    self.seed = None
    self.dst_mac_addr = None
    self.src_mac_addr = None
    self.vlan_prio_tag = None
    self.ether_len_type = None
    self.create_data_args = None
    self.send_header = True

    # Get all other values from the dictionary passed in
    for arg,value in kwargs.iteritems():
      setattr(self, arg, value)

    # Preamble nibbles - define valid preamble by default
    if self.preamble_nibbles is None:
        self.preamble_nibbles = [0x5 for x in range(self.num_preamble_nibbles)]

    # Destination MAC address - use a random one if not user-defined
    if self.dst_mac_addr is None:
      self.dst_mac_addr = [x for x in nprand.randint(256, size=6)]

    # Source MAC address - use a random one if not user-defined
    if self.src_mac_addr is None:
      self.src_mac_addr = [x for x in nprand.randint(256, size=6)]

    # If the data is defined, then record the length. Otherwise create random
    # data of the length specified
    if self.data_bytes is None and not blank:
      if self.create_data_args:
        self.data_bytes = create_data(self.create_data_args)
      else:
        self.data_bytes = [x for x in nprand.randint(256, size=self.num_data_bytes)]

    # Ensure that however the data has been created, the length is correct
    if self.data_bytes is None:
      self.num_data_bytes = 0
    else:
      self.num_data_bytes = len(self.data_bytes)

    # Nibble count primarily used for packet receive, but keep it valid here
    self.num_data_nibbles = 2 * self.num_data_bytes

    # If the ether length/type field is not specified then set it to something sensible
    if self.ether_len_type is None:
      if self.ether_len_type <= self.MAX_ETHER_LEN:
        self.ether_len_type = [ (self.num_data_bytes >> 8) & 0xff, self.num_data_bytes & 0xff ]
      else:
        self.ether_len_type = [ 0x00, 0x00 ]
  
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

  def get_nibbles(self):
    nibbles = self.preamble_nibbles

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
      nibbles.append(nprand.randint(256))

    return nibbles

  def append_preamble_nibble(self, nibble):
    if self.preamble_nibbles is None:
      self.preamble_nibbles = []
    self.preamble_nibbles.append(nibble)
    self.num_preamble_nibbles = len(self.preamble_nibbles)

  def set_sfd_nibble(self, nibble):
    self.sfd_nibble = nibble
    
  def append_data_nibble(self, nibble):
    if self.data_bytes is None:
      self.data_bytes = []
    if (self.num_data_nibbles % 2) == 0:
      self.data_bytes.append(nibble)
    else:
      self.data_bytes[-1] = self.data_bytes[-1] + (nibble << 4)
      
    self.num_data_nibbles += 1
    
  def check(self, clock):
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

    if (self.num_data_nibbles % 2) != 0:
      print "ERROR: Odd number of data nibbles transmitted: {0}".format(self.num_preamble_nibbles)

    # Check the CRC
    packet_crc = (self.data_bytes[-4] + (self.data_bytes[-3] << 8) + 
                  (self.data_bytes[-2] << 16) + (self.data_bytes[-1] << 24))
    data = ''.join(chr(x) for x in self.data_bytes[:-4])
    expected_crc = zlib.crc32(data) & 0xFFFFFFFF

    # UNH-IOL MAC Test 4.2.3
    if packet_crc != expected_crc:
      print "ERROR: Invalid crc (got {got}, expecting {expect})".format(got=packet_crc, expect=expected_crc)

  def dump(self):
    # Discount the CRC word from the bytes received
    sys.stdout.write("Packet len={len}, dst=[{dst}], src=[{src}], len/type=[{lt}]\n".format(
      len=(self.num_data_bytes),
      dst=" ".join(["0x{0:0>2x}".format(i) for i in self.dst_mac_addr]),
      src=" ".join(["0x{0:0>2x}".format(i) for i in self.src_mac_addr]),
      lt=" ".join(["0x{0:0>2x}".format(i) for i in self.ether_len_type])))
    sys.stdout.write("data=[\n  ")
    for i,x in enumerate(self.data_bytes):
      if i and ((i%16) == 0):
        sys.stdout.write("\n  ")
      sys.stdout.write("0x{0:0>2x}, ".format(x))
    sys.stdout.write("\n]\n")
    if self.send_crc_word:
      crc = self.get_crc(self.get_packet_bytes())
      sys.stdout.write("CRC: 0x{0:0>2x}\n".format(crc))
        
  def __str__(self):
    return "{0} preamble nibbles, {1} data bytes".format(self.num_preamble_nibbles, self.num_data_bytes)
  
