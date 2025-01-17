# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import Pyxsim as px
from bitstring import BitArray, BitStream

VERBOSE = False

class smi_master_checker(px.SimThread):
    """"
    This simulator thread will act as SMI slave and check any transactions
    sent by the master.
    """

    def __init__(self, mdc_port, mdio_port, rst_n_port, expected_speed_hz, tx_data=[], mdc_mdio_bit_pos=None):
      # ports and data
      self._mdc_port = mdc_port
      self._mdio_port = mdio_port
      self._mdc_mdio_bit_pos = mdc_mdio_bit_pos
      self._rst_n_port = rst_n_port

      # Data to send
      self._tx_data =[[int(bit) for bit in BitArray(uint=tx_word, length=16).bin] for tx_word in tx_data]

      # Bit rate
      self._expected_speed_hz = expected_speed_hz
    
      # These values are used to simulate pull-ups
      self._external_mdc_value = 1
      self._external_mdio_value = 1

      # pin states
      self._mdc_change_time = None
      self._mdio_change_time = None
      self._last_mdio_change_time = None
      self._mdc_value = 0
      self._mdio_value = 0

      # Test state
      self._test_running = False

      self._reset_smi_state_machine()

      print("Checking SMI: MDC=%s, MDIO=%s RST_N=%s" % (self._mdc_port, self._mdio_port, self._rst_n_port))

    def _reset_smi_state_machine(self):
      # State of transaction
      self._bit_num = 0
      self._bit_times = []
      self._prev_fall_time = None

      # Packet info
      self._data = [] # Running data accumulator
      self._state = "idle"
      self._preamble = None
      self._start_of_frame = None
      self._op_code = None
      self._phy_addr = None
      self._reg_addr = None
      self._turnaround = None
      self._read_data = None
      self._write_data = None

    def _calculate_ave_bit_time(self):
      # we have 63 periods in between the bit times here (fencepost thing) not 64
      max_bit_time = max(self._bit_times)
      min_bit_time = min(self._bit_times)
      ave_bit_time = sum(self._bit_times)/self._bit_num

      if VERBOSE:
        print(f"Average bit time: {ave_bit_time/1e6:.2f}ns ({1e9/ave_bit_time:.2f}MHz)")
        print(f"Min bit time: {min_bit_time/1e6:.2f}ns ({1e9/min_bit_time:.2f}MHz)")
        print(f"Max bit time: {max_bit_time/1e6:.2f}ns ({1e9/max_bit_time:.2f}MHz)")

      max_bit_freq_hz = 1e15 / min_bit_time
      if(max_bit_freq_hz > self._expected_speed_hz):
        self.error(f"Max MDC rate {max_bit_freq_hz} higher than expected {self._expected_speed_hz}")

    def error(self, str):
         print("ERROR: %s @ %s" % (str, self.xsi.get_time()))

    # We use this helper to implement a virtual pull-up resistor
    def read_port(self, port, external_value):
      driving = self.xsi.is_port_driving(port)
      if driving:
        value = self.xsi.sample_port_pins(port)
      else:
        value = external_value
        # Maintain the weak external drive
        self.xsi.drive_port_pins(port, external_value)
      # print("READ {}: drive {}, val: {} (ext: {}) @ {}".format(port, driving, value, external_value, self.xsi.get_time()))
      return value

    def read_mdc_value(self):
      return self.read_port(self._mdc_port, self._external_mdc_value)

    def read_mdio_value(self):
      return self.read_port(self._mdio_port, self._external_mdio_value)

    def read_rst_n_value(self):
      port_val = self.xsi.sample_port_pins(self._rst_n_port)
      if port_val & 0x1:
        return 1
      else:
        return 0

    def drive_mdio(self, value):
       # Cache the value that is currently being driven
       self._external_mdio_value = value
       self.xsi.drive_port_pins(self._mdio_port, value)

    def get_next_data_item(self):
        if self._tx_data_index >= len(self._tx_data):
            return 0xab
        else:
            data = self._tx_data[self._tx_data_index]
            self._tx_data_index += 1
            return data


    def wait_for_change(self):
      """ Wait for either the MDIO/MDC port to change and return which one it was.
          Need to also maintain the drive of any value set by the user.
      """
      mdc_changed = False
      mdio_changed = False

      mdc_value = self._mdc_value
      mdio_value = self._mdio_value

      # The value might already not be the same if both signals transitioned
      # simultaneously previously
      new_mdc_value = self.read_mdc_value()
      new_mdio_value = self.read_mdio_value()
      while new_mdc_value == mdc_value and new_mdio_value == mdio_value:
        self.wait_for_port_pins_change([self._mdc_port, self._mdio_port, self._rst_n_port])

        # Logic to exit test when reset driven low by FW
        if self._test_running and self.xsi.sample_port_pins(self._rst_n_port) == 0x0:
          self.xsi.terminate()
        if not self._test_running and self.xsi.sample_port_pins(self._rst_n_port) == 0xf:
          self._test_running = True

        new_mdc_value = self.read_mdc_value()
        new_mdio_value = self.read_mdio_value()

      time_now = self.xsi.get_time()

      if VERBOSE:
        print(f"wait_for_change mdc:{mdc_value}, mdio:{mdio_value} -> mdc:{new_mdc_value}, mdio:{new_mdio_value} @ {time_now}")


      # Check to see if we are in reset. If so, ignore all and reset state machine
      if self.read_rst_n_value() == 0:
        self._reset_smi_state_machine()
        self._mdc_value = new_mdc_value
        self._mdio_value = new_mdio_value

        return mdc_changed, mdio_changed

    
      # MDC changed
      if mdc_value != new_mdc_value:
        mdc_changed = True

        self._mdc_change_time = time_now
        self._mdc_value = new_mdc_value

        # Record the time of the rising edges
        if new_mdc_value == 1:
          fall_time = self.xsi.get_time()
          if self._prev_fall_time is not None:
            self._bit_times.append(fall_time - self._prev_fall_time)
          self._prev_fall_time = fall_time

      # MDIO changed - don't detect simultaneous changes and have the clock be higher priority if they do.
      if not mdc_changed and (mdio_value != new_mdio_value):
        mdio_changed = True
        self._last_mdio_change_time = self._mdio_change_time
        self._mdio_change_time = time_now
        self._mdio_value = new_mdio_value

        # if new_mdc_value == 0:
        #   self.check_data_valid_time(time_now - self._mdc_change_time)

      return mdc_changed, mdio_changed

    # This all happens on the rising edge
    def decode_frame_on_rising(self):
      # start of transaction
      if self._bit_num == 0:
          self._state = "preamble"

      # end of preamble
      elif self._bit_num == 31:
          self._preamble = self._data
          self._data = []
          if self._preamble != [1] * 32:
             self.error(f"Invalid preamble: {self._preamble}")
          self._state = "start_of_frame"

      # end of SoF
      elif self._bit_num == 33:
          self._start_of_frame = self._data
          self._data = []
          if self._preamble != [1] * 32:
             self.error(f"Invalid start_of_frame: {self._start_of_frame}")
          self._state = "op_code"
      
      # end of opcode
      elif self._bit_num == 35:
          self._op_code = self._data
          self._data = []

          # read
          if self._op_code == [1, 0]:
            if(len(self._tx_data) < 1):
              self.error("Run out of data to transmit / SMI read")
            self._tx_word = self._tx_data[0]
            del self._tx_data[0]
          # write
          elif self._op_code == [0, 1]:
            pass
          else:
             self.error(f"Invalid opcode: {self._op_code}")
          self._state = "phy_address"

      # end of phy_address
      elif self._bit_num == 40:
          self._phy_addr = self._data
          self._data = []
          self._state = "reg_address"

      #end of reg address
      elif self._bit_num == 45:
          self._reg_addr = self._data
          self._data = []
          self._state = "turnaround"

      # Turnaround
      elif self._bit_num == 47:
          self._turnaround = self._data
          self._data = []
          if self._op_code == [1, 0]:
              self._state = "read"
          elif self._op_code == [0, 1]:
              self._state = "write"
          else:
              self._state = "invalid_op_code"

      elif self._bit_num == 63:
          if self._state == "write":
              self._write_data = self._data
              self._data = []
              written_data = BitArray(self._write_data).uint
              print(f"DUT WRITE: 0x{written_data:x}")


          elif self._state == "read":
              pass            

          self._calculate_ave_bit_time()
          self._reset_smi_state_machine()
          self._bit_num = -1

      elif self._bit_num > 63:
          self.error("Bit number exceed 63")


    def drive_frame_on_rising(self):
      # Start read 
      if self._bit_num >= 46 and self._state == "read":
        value = self._tx_word[0]
        self.drive_mdio(value);
        # print(f"sending mdio: {value} {self.xsi.get_time()/1e9:.2f}us driving: {self.xsi.is_port_driving(self._mdio_port)}")
        del self._tx_word[0]

    def move_to_next_state(self, mdc_changed, mdio_changed):
      if mdc_changed:
        # Rising edge of MDC
        if self._mdc_value == 1:
          # print(f"Got MDIO bit {self._bit_num}: {self._mdio_value} at time {self._mdc_change_time}")
          self._data.append(self._mdio_value)
          self.decode_frame_on_rising()
          self.drive_frame_on_rising()          
          self._bit_num += 1

        if self._mdc_value == 0:
          pass # Do nothing on falling edge


    def run(self):
      # Simulate external pullup
      self.drive_mdio(1)

      self._mdc_value = self.read_mdc_value()
      self._mdio_value = self.read_mdio_value()

      # self.wait_for_stopped()

      self._tx_data_index = 0


      while True:
        mdc_changed, mdio_changed = self.wait_for_change()

        if mdc_changed and mdio_changed:
          self.error("Unsupported having MDC & MDIO changing simultaneously")

        self.move_to_next_state(mdc_changed, mdio_changed)


# Will make an SMI packet. If write_data is not specified we assume a read.
# Data is returned as a BitArray - get that as 1s and 0s using header.bin and wr_data.bin
def smi_make_packet(phy_address, reg_address, write_data=None):
    if phy_address > 0x1f or reg_address > 0x1f:
        print(f"Error: phy address 0x{phy_address:x} and reg address 0x{reg_address:x} must be less than 31")

    preamble = BitArray(bin='1' * 32) 
    sof = BitArray(bin='01')
    opcode = BitArray(bin='10' if write_data == None else '01')
    phy_addr = BitArray(uint=phy_address, length=5)
    reg_addr = BitArray(uint=reg_address, length=5)

    header = preamble + sof + opcode + phy_addr + reg_addr
    
    # TODO debug only
    print(opcode.bin)
    print(phy_addr)
    print(reg_addr)
    print(header.bin)

    # Note we need a two cycle Hi-Z turnaround between header and read or write data

    print(write_data)
    if write_data is None:
        wr_data = None
    else:
        # Data is always 16bits
        if write_data > 0xffff:
            print(f"Error: write_data 0x{write_data} must be 16 bits")
        wr_data = BitArray(uint=write_data, length=16)

    return header, wr_data