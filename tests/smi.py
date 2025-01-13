# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import Pyxsim as px

VERBOSE = False

class smi_master_checker(px.SimThread):
    """"
    This simulator thread will act as SMI slave and check any transactions
    caused by the master.
    """

    def __init__(self, mdc_port, mdio_port, expected_speed,
                 tx_data=[], ack_sequence=[], clock_stretch=0, original_speed=None):
        self._mdc_port = mdc_port
        self._mdio_port = mdio_port
        self._tx_data = tx_data
        self._ack_sequence = ack_sequence
        self._expected_speed = expected_speed # Speed the checker is expected to detect. Could be lower than the I2C master's original operating speed if the slave is clock stretching
        self._clock_stretch = clock_stretch*1e6 # ns to fs conversion

        self._external_mdc_value = 0
        self._external_mdio_value = 0

        self._mdc_change_time = None
        self._mdio_change_time = None
        self._last_mdio_change_time = None
        self._mdc_value = 0
        self._mdio_value = 0

        self._clock_release_time = None

        self._bit_num = 0
        self._bit_times = []
        self._prev_fall_time = None
        self._byte_num = 0

        self._read_data = None
        self._write_data = None

        self._drive_ack = 1
        if original_speed is not None:
          self._original_speed = original_speed # Speed at which the I2C master is operating.
        else:
          self._original_speed = self._expected_speed

        print("Checking SMI: MDC=%s, MDIO=%s" % (self._mdc_port, self._mdio_port))

    def error(self, str):
         print("ERROR: %s @ %s" % (str, self.xsi.get_time()))

    def read_port(self, port, external_value):
      driving = self.xsi.is_port_driving(port)
      if driving:
        value = self.xsi.sample_port_pins(port)
      else:
        value = external_value
        # Maintain the weak external drive
        self.xsi.drive_port_pins(port, external_value)
      # print "READ {}, got {}, {} ({}) @ {}".format(
      #   port, driving, value, external_value, self.xsi.get_time())
      return value

    def read_mdc_value(self):
      return self.read_port(self._mdc_port, self._external_mdc_value)

    def read_mdio_value(self):
      return self.read_port(self._mdio_port, self._external_mdio_value)

    def drive_mdio(self, value):
       # Cache the value that is currently being driven
       self._external_mdio_value = value
       self.xsi.drive_port_pins(self._mdio_port, value)

    def check_data_valid_time(self, time):
        if time < 0:
            # Data change must have been for a previous bit
            return

        if (self._original_speed == 100 and time > 3450e6) or\
           (self._original_speed == 400 and time >  900e6):
            self.error("Data valid time not respected: %gns" % time)

    def check_hold_start_time(self, time):
        if (self._original_speed == 100 and time < 4000e6) or\
           (self._original_speed == 400 and time < 600e6):
            self.error(f"Start hold time less than minimum in spec: %gfs" % time)

    def check_setup_start_time(self, time):
        if (self._original_speed == 100 and time < 4700e6) or\
           (self._original_speed == 400 and time < 600e6):
            self.error(f"Start bit setup time less than minimum in spec: %gfs" % time)

    def check_data_setup_time(self, time):
        if (self._original_speed == 100 and time < 250e6) or\
           (self._original_speed == 400 and time < 100e6):
            self.error("Data setup time less than minimum in spec: %gfs" % time)

    def check_clock_low_time(self, time):
        if (self._original_speed == 100 and time < 4700e6) or\
           (self._original_speed == 400 and time < 1300e6):
            self.error("Clock low time less than minimum in spec: %gfs" % time)

    def check_clock_high_time(self, time):
        if (self._original_speed == 100 and time < 4000e6) or\
           (self._original_speed == 400 and time < 900e6):
            self.error("Clock high time less than minimum in spec: %gfs" % time)

    def check_setup_stop_time(self, time):
        if (self._original_speed == 100 and time < 4000e6) or\
           (self._original_speed == 400 and time < 600e6):
            self.error("Stop bit setup time less than minimum in spec: %gfs" % time)

    def get_next_data_item(self):
        if self._tx_data_index >= len(self._tx_data):
            return 0xab
        else:
            data = self._tx_data[self._tx_data_index]
            self._tx_data_index += 1
            return data

    states = {
      #                      EXPECT     |  Next state on transition of
      # STATE            :   SCL,  SDA  |  SCL       SDA
      #

      "STOPPED"          : ( 1,    1,     "ILLEGAL",          "STARTING" ),
      "STARTING"         : ( 1,    0,     "DRIVE_BIT",        "ILLEGAL" ),
      "DRIVE_BIT"        : ( 0,    None,  "SAMPLE_BIT",       "DRIVE_BIT" ),
      "SAMPLE_BIT"       : ( 1,    None,  "DRIVE_BIT",        "CHECK_START_STOP" ),
      "CHECK_START_STOP" : ( 1,    None,  "DRIVE_BIT",        "ILLEGAL" ),
      "BYTE_DONE"        : ( None, None,  "DRIVE_ACK",        "ILLEGAL" ),
      "DRIVE_ACK"        : ( 0,    None,  "SAMPLE_ACK",       "DRIVE_ACK" ),
      "ACK_SENT"         : ( 0,    None,  "SAMPLE_ACK",       "ACK_SENT" ),
      # This state will be transitioned by the handler
      "SAMPLE_ACK"       : ( 1,    None,  "NOT_POSSIBLE",     "NOT_POSSIBLE" ),
      "ACKED"            : ( None, None,  "DRIVE_BIT",        "ACKED" ),
      "NACKED"           : ( None, None,  "DRIVE_BIT",        "NACKED" ),
      "REPEAT_START"     : ( 1,    0,     "DRIVE_BIT",        "ILLEGAL" ),
      "ILLEGAL"          : ( None, None,  "ILLEGAL",          "ILLEGAL" ),
    }

    @property
    def expected_mdc(self):
      return self.states[self._state][0]

    @property
    def expected_mdio(self):
      return self.states[self._state][1]

    def wait_for_stopped(self):
      while self._mdc_value != 1 or self._mdio_value != 1:
        self.wait_for_port_pins_change([self._mdc_port, self._mdio_port])
        self._mdc_value = self.read_mdc_value()
        self._mdio_value = self.read_mdio_value()

    def wait_for_change(self):
      """ Wait for either the SDA/SCL port to change and return which one it was.
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
        if self._clock_release_time is not None:
          # When clock stretching it is necessary simply to clock the simulation
          # as there is no wait for data change with timeout
          self.wait_for_next_cycle()
          if self.xsi.get_time() >= self._clock_release_time:
            self.drive_mdc(1)
            self._clock_release_time = None
            if VERBOSE:
              print("End clock stretching @ {}".format(self.xsi.get_time()))

        else:
          # Default case, simply wait for one of the pins to change
          self.wait_for_port_pins_change([self._mdc_port, self._mdio_port])

        new_mdc_value = self.read_mdc_value()
        new_mdio_value = self.read_mdio_value()

      time_now = self.xsi.get_time()

      if VERBOSE:
        print("wait_for_change {},{} -> {},{} @ {}".format(
          mdc_value, mdio_value, new_mdc_value, new_mdio_value, time_now))

      #
      # SCL changed
      #
      if mdc_value != new_mdc_value:
        mdc_changed = True

        # Ensure the clock timing is correct
        if self._mdc_change_time:
          if new_mdc_value == 0:
            self.check_clock_high_time(time_now - self._mdc_change_time)
          else:
            self.check_clock_low_time(time_now - self._mdc_change_time)

        self._mdc_change_time = time_now
        self._mdc_value = new_mdc_value

        # Record the time of the falling edges
        if new_mdc_value == 0:
          fall_time = self.xsi.get_time()
          if self._prev_fall_time is not None:
            self._bit_times.append(fall_time - self._prev_fall_time)
          self._prev_fall_time = fall_time

        # Stretch the clock if required
        if self._clock_stretch and new_mdc_value == 0:
          self.drive_mdc(0)
          self._clock_release_time = time_now + self._clock_stretch
          if VERBOSE:
            print("Start clock stretching @ {}".format(self.xsi.get_time()))

      #
      # SDA changed - don't detect simultaneous changes and have the clock
      # be higher priority if they do.
      #
      if not mdc_changed and (mdio_value != new_mdio_value):
        mdio_changed = True
        self._last_mdio_change_time = self._mdio_change_time
        self._mdio_change_time = time_now
        self._mdio_value = new_mdio_value

        if new_mdc_value == 0:
          self.check_data_valid_time(time_now - self._mdc_change_time)

      return mdc_changed, mdio_changed

    def set_state(self, next_state):
      if VERBOSE:
        print("State: {} -> {} @ {}".format(self._state, next_state, self.xsi.get_time()))
      self._prev_state = self._state
      self._state = next_state

      # Ensure the current state of the SCL/SDA is valid
      self.check_mdc_mdio_lines()

      # Execute the handler for the state
      handler = getattr(self, "handle_" + self._state.lower())
      handler()

    def move_to_next_state(self, mdc_changed, mdio_changed):
      if mdc_changed:
        next_state = self.states[self._state][2]
      else:
        next_state = self.states[self._state][3]
      self.set_state(next_state)

    def check_value(self, value, expected, name):
      if expected is not None:
        if value != expected:
          self.error("{}: {} != {}".format(self._state, name, expected))

    def check_mdc_mdio_lines(self):
      self.check_value(self.read_mdc_value(), self.expected_mdc, "SCL")
      self.check_value(self.read_mdio_value(), self.expected_mdio, "SDA")

    def start_read(self):
      self._bit_num = 0
      self._bit_times = []
      self._prev_fall_time = None
      self._read_data = 0
      self._write_data = None

    def start_write(self):
      self._bit_num = 0
      self._bit_times = []
      self._prev_fall_time = None
      self._read_data = None
      self._write_data = self.get_next_data_item()

    def byte_done(self):
      if self._read_data is not None:
        print("Byte received: 0x%x" % self._read_data)
        self._drive_ack = 1
      else:
        # Reads are acked by the master
        self._drive_ack = 0
        print("Byte sent")

      if self._bit_times:
        avg_bit_time = sum(self._bit_times) / len(self._bit_times)
        speed_in_kbps = pow(10, 12) / avg_bit_time
        print("Speed = %d Kbps" % int(speed_in_kbps + .5))
        if self._expected_speed != None and \
          (speed_in_kbps < 0.99 * self._expected_speed):
           print("ERROR: speed is <1% slower than expected")

        if self._expected_speed != None and \
          (speed_in_kbps > self._expected_speed * 1.05):
           print("ERROR: speed is faster than expected")

      if self._byte_num == 0:
        # Command byte

        # The command is always acked by the slave
        self._drive_ack = 1

        # Determine whether it is starting a read or write
        mode = self._read_data & 0x1
        print("Master %s transaction started, device address=0x%x" %
              ("write" if mode == 0 else "read", self._read_data >> 1))

        if mode == 0:
          self.start_read()
        else:
          self.start_write()

      else:
        if self._read_data is not None:
          self.start_read()

      self.set_state("BYTE_DONE")

    #
    # Handler functions for each state
    #
    def handle_stopped(self):
      print("Stop bit received")
      self.check_setup_stop_time(self._mdio_change_time - self._mdc_change_time)
      pass

    def starting_sequence(self):
      self._byte_num = 0
      self.start_read()
      if self._last_mdio_change_time is not None:
        self.check_bus_free_time(self.xsi.get_time() - self._last_mdio_change_time)

    def handle_drive_bit(self):
      if self._mdio_change_time is not None and \
        (self._prev_state == "STARTING" or self._prev_state == "REPEAT_START") :
        # Need to check that the start hold time has been respected
        self.check_hold_start_time(self.xsi.get_time() - self._mdio_change_time)

      if self._write_data is not None:
        # Drive data being read by master
        self.drive_mdio((self._write_data & 0x80) >> 7)
      else:
        # Simulate external pullup
        self.drive_mdio(1)

    def handle_starting(self):
      print("Start bit received")
      if self._mdc_change_time:
        self.check_setup_start_time(self._mdio_change_time - self._mdc_change_time)
      self.starting_sequence()

    def handle_sample_bit(self):
      if self._read_data is not None:
        # Ensure that the data setup time has been respected
        self.check_data_setup_time(self.xsi.get_time() - self._mdio_change_time)

        # Read the data value
        self._read_data = (self._read_data << 1) | self.read_mdio_value()

      if self._write_data is not None:
        self._write_data = (self._write_data << 1) & 0xff

      self._bit_num += 1
      if self._bit_num == 8:
        self.byte_done()

    def handle_check_start_stop(self):
      if self._mdio_value:
        if self._bit_num != 1:
          self.error("Stopping when mid-byte")
        self.set_state("STOPPED")
      else:
        if self._bit_num != 1:
          self.error("Start bit detected mid-byte")
          self.set_state("STARTING")
        else:
          self.set_state("REPEAT_START")

    def handle_byte_done(self):
      pass

    def handle_drive_ack(self):
      if self._drive_ack:
        ack = self.get_next_ack()
        if ack:
          print("Sending ack")
          self.drive_mdio(0)
        else:
          print("Sending nack")
          self.drive_mdio(1)
        self.set_state("ACK_SENT")
      else:
        # Simulate external pullup
        self.drive_mdio(1)


    def handle_repeat_start(self):
      print("Repeated start bit received")
      # Need to check setup time for repeated start has been respected
      self.check_setup_start_time(self._mdio_change_time - self._mdc_change_time)
      self.starting_sequence()

    def handle_illegal(self):
      self.error("Illegal state arrived at from {}".format(self._prev_state))

    def run(self):
      # Simulate external pullup
      self.drive_mdc(1)
      self.drive_mdio(1)

      # Ignore the blips on the ports at the start
      self.wait_until(100e6)
      self._mdc_value = self.read_mdc_value()
      self._mdio_value = self.read_mdio_value()

      self.wait_for_stopped()

      self._tx_data_index = 0
      self._ack_index = 0

      self._state = "STOPPED"

      while True:
        mdc_changed, mdio_changed = self.wait_for_change()

        if mdc_changed and mdio_changed:
          self.error("Unsupported having SCL & SDA changing simultaneously")

        self.move_to_next_state(mdc_changed, mdio_changed)