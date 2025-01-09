# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import random
import Pyxsim as px
import sys
import zlib
from mii_packet import MiiPacket
import re

def get_port_width_from_name(port_name):
    """
        Get port width from port name. For example, for the port name 'tile[0]:XS1_PORT_4F',
        return port width as 4
    """
    m = re.search(r'XS1_PORT_([0-9])\D', port_name)
    assert m, f"Cannot find port width. Unexpected port name {port_name}"
    return int(m.group(1))


class RMiiTxPhy(px.SimThread):

    # Time in fs from the last packet being sent until the end of test is signalled to the DUT
    END_OF_TEST_TIME = (10 * px.Xsi.get_xsi_tick_freq_hz())/1e6 # 10us

    def __init__(self, name, rxd, rxdv, rxer, clock,
                 rxd_4b_port_pin_assignment,
                 initial_delay_us, verbose,
                 test_ctrl, do_timeout, complete_fn, expect_loopback, dut_exit_time_us):
        self._name = name
        self._test_ctrl = test_ctrl
        # Check if rxd is a string or an array of strings
        if not isinstance(rxd, (list, tuple)):
            rxd = [rxd]
        assert len(rxd) == 1 or len(rxd) == 2, f"Invalid rxd array length {len(rxd)}. rxd = {rxd}"

            # 1b ports will always be in a length=2 list. 4b port can be a length=1 list or just a string
        self._rxd = rxd
        self._rxdv = rxdv
        self._rxer = rxer
        self._packets = []
        self._clock = clock
        self._rxd_4b_port_pin_assignment = rxd_4b_port_pin_assignment
        self._initial_delay = initial_delay_us
        self._verbose = verbose
        self._do_timeout = do_timeout
        self._complete_fn = complete_fn
        self._expect_loopback = expect_loopback
        self._dut_exit_time = dut_exit_time_us
        self._rxd_port_width = get_port_width_from_name(self._rxd[0])
        if len(self._rxd) == 2:
            assert self._rxd_port_width == 1, f"Only 1bit ports allowed when specifying 2 ports. {self._rxd}"
            port_width_check = get_port_width_from_name(self._rxd[1])
            assert self._rxd_port_width == port_width_check, f"When specifying 2 ports, both need to be of width 1bit. {self._rxd}"
        else:
            assert self._rxd_port_width == 4, f"Only 4bit port allowed when specifying only 1 port. {self._rxd}"

        if self._rxd_port_width == 4:
            assert self._rxd_4b_port_pin_assignment == "lower_2b" or self._rxd_4b_port_pin_assignment == "upper_2b", \
                f"Invalid rxd_4b_port_pin_assignment (self._rxd_4b_port_pin_assignment). Allowed values lower_2b or upper_2b"


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
            print("All packets sent")

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
                timeout_time += 2 * total_data_bits * 1e6 # scale to femtoseconds vs nanoseconds in old xsim

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

            print("ERROR: Test timed out")
            self.xsi.terminate()

    def set_clock(self, clock):
        self._clock = clock

    def set_packets(self, packets):
        self._packets = packets

    def drive_error(self, value):
        self.xsi.drive_port_pins(self._rxer, value)

class PacketManager():
    def __init__(self, packets, clock, data_type, verbose=False):
        assert data_type in ['crumb', 'nibble']
        self._data_type = data_type # 'nibble' or 'crumb'
        self._pkts = packets
        self._num_pkts = len(self._pkts)
        self._pkt_ended = False # Flag indicating if the current packet has ended
        self._verbose = verbose
        self._clock = clock

        # Set up to do the first packet
        self._current_pkt_index = 0
        if len(self._pkts):
            self._pkt = self._pkts[self._current_pkt_index]
            self._nibbles = self._pkt.get_nibbles() # list of nibbles in the current packet
            self._error_nibbles = self._pkt.get_error_nibbles()
            self._nibble_index = 0 # nibble we're indexing in the current packet
            self._crumb_index = 0 # alternates between 0 and 1
            self._ifg_wait_cycles = 0

    def get_data(self):
        if(self._current_pkt_index == self._num_pkts): # Finished all the packets
            return None, False, False

        # From IFG in xsi ticks, derive IFG in clock cycles.
        # IFG_xsi_ticks/xsi_ticks_per_bit = IFG_in_no_of_bits
        # IFG_in_no_of_bits/bits_per_clock_cycle = ifg_in_clock_cycles
        ifg_clock_cycles = self._pkt.inter_frame_gap/(self._clock._bit_time * self._clock.get_clock_cycle_to_bit_time_ratio())
        if self._ifg_wait_cycles < ifg_clock_cycles: # ifg in clock cycles
            self._ifg_wait_cycles += 1
            return None, False, True

        self._pkt_ended = False
        if self._nibble_index in self._error_nibbles:
            error = True
        else:
            error = False

        if self._data_type == 'nibble':
            if self._verbose and self._nibble_index == 0:
                print(f"Sending packet {self._current_pkt_index}: {self._pkt}")
                sys.stdout.write(self._pkt.dump())
            dataval = self._nibbles[self._nibble_index]
            self._nibble_index = self._nibble_index + 1
        else: # crumb
            if self._verbose and self._nibble_index == 0 and self._crumb_index == 0:
                print(f"Sending packet {self._current_pkt_index}: {self._pkt}")
                sys.stdout.write(self._pkt.dump())
            dataval = (self._nibbles[self._nibble_index] >> (self._crumb_index*2)) & 0x3
            self._crumb_index = self._crumb_index ^ 1
            if self._crumb_index == 0:
                self._nibble_index = self._nibble_index + 1

        if self._nibble_index == len(self._nibbles): # End of current packet. Set up for the next packet
            self._pkt_ended = True
            if self._verbose:
                print(f"Sent")
            self._current_pkt_index = self._current_pkt_index + 1
            if self._current_pkt_index < self._num_pkts:
                self._pkt = self._pkts[self._current_pkt_index]
                self._nibbles = self._pkt.get_nibbles()
                self._error_nibbles = self._pkt.get_error_nibbles()
                self._nibble_index = 0
                self._crumb_index = 0
                self._ifg_wait_cycles = 0


        return dataval, error, False

    def pkt_ended(self): # Return True if current packet has ended
        return self._pkt_ended

    def get_current_pkt_ifg(self):
        return self._pkt.inter_frame_gap

class RMiiTransmitter(RMiiTxPhy):

    def __init__(self, rxd, rxdv, rxer, clock,
                 rxd_4b_port_pin_assignment="lower_2b",
                 initial_delay_us=(85 * px.Xsi.get_xsi_tick_freq_hz())/1e6, verbose=False, test_ctrl=None,
                 do_timeout=True, complete_fn=None, expect_loopback=True,
                 dut_exit_time_us=(25 * px.Xsi.get_xsi_tick_freq_hz())/1e6):
        super(RMiiTransmitter, self).__init__('rmii', rxd, rxdv, rxer, clock,
                                             rxd_4b_port_pin_assignment,
                                             initial_delay_us, verbose, test_ctrl,
                                             do_timeout, complete_fn, expect_loopback,
                                             dut_exit_time_us)

    def run(self):
        xsi = self.xsi
        pkt_manager = PacketManager(self._packets, self._clock, "crumb", verbose=self._verbose) # read packet data at crumb granularity
        self.start_test()

        while True:
            self.wait(lambda x: self._clock.is_high())

            if pkt_manager.pkt_ended():
                xsi.drive_port_pins(self._rxdv, 0)
                xsi.drive_port_pins(self._rxer, 0)


            data, drive_error, ifg_wait = pkt_manager.get_data()
            if ifg_wait == False:
                if data == None: # No more data to send
                    break

                xsi.drive_port_pins(self._rxdv, 1)

                if self._rxd_port_width == 4:
                    if self._rxd_4b_port_pin_assignment == "lower_2b":
                        xsi.drive_port_pins(self._rxd[0], data)
                        #print(f"crumb = {data:x}")
                    else:
                        xsi.drive_port_pins(self._rxd[0], (data << 2))
                else: # 2, 1bit ports
                    xsi.drive_port_pins(self._rxd[0], data & 0x1)
                    xsi.drive_port_pins(self._rxd[1], (data >> 1) & 0x1)

                # Signal an error if required
                if drive_error == True:
                    xsi.drive_port_pins(self._rxer, 1)
                else:
                    xsi.drive_port_pins(self._rxer, 0)

            self.wait(lambda x: self._clock.is_low())



        self.end_test()


class RMiiRxPhy(px.SimThread):

    def __init__(self, name, txd, txen, clock, txd_4b_port_pin_assignment, print_packets, packet_fn, verbose, test_ctrl):
        self._name = name
        # Check if txd is a string or an array of strings
        if not isinstance(txd, (list, tuple)):
            txd = [txd]
        assert len(txd) == 1 or len(txd) == 2, f"Invalid txd array length {len(txd)}. txd = {txd}"
        self._txd = txd
        self._txen = txen
        self._clock = clock
        self._txd_4b_port_pin_assignment = txd_4b_port_pin_assignment
        self._print_packets = print_packets
        self._verbose = verbose
        self._test_ctrl = test_ctrl
        self._packet_fn = packet_fn

        self._txd_port_width = get_port_width_from_name(self._txd[0])
        if len(self._txd) == 2:
            assert self._txd_port_width == 1, f"Only 1bit ports allowed when specifying 2 ports. {self._txd}"
            port_width_check = get_port_width_from_name(self._txd[1])
            assert self._txd_port_width == port_width_check, f"When specifying 2 ports, both need to be of width 1bit. {self._txd}"
        else:
            assert self._txd_port_width == 4, f"Only 4bit port allowed when specifying only 1 port. {self._txd}"

        if self._txd_port_width == 4:
            assert self._txd_4b_port_pin_assignment == "lower_2b" or self._txd_4b_port_pin_assignment == "upper_2b", \
                f"Invalid txd_4b_port_pin_assignment (self._txd_4b_port_pin_assignment). Allowed values lower_2b or upper_2b"

        self.expected_packets = None
        self.expect_packet_index = 0
        self.num_expected_packets = 0

        self.expected_packets = None
        self.expect_packet_index = 0
        self.num_expected_packets = 0
        #print(f"self._txd = {self._txd}, self._txd_port_width = {self._txd_port_width}, self._txd_4b_port_pin_assignment = {self._txd_4b_port_pin_assignment}")

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


class RMiiReceiver(RMiiRxPhy):

    def __init__(self, txd, txen, clock,
                 txd_4b_port_pin_assignment="lower_2b",
                 print_packets=False,
                 packet_fn=None, verbose=False, test_ctrl=None):
        super(RMiiReceiver, self).__init__('rmii', txd, txen, clock, txd_4b_port_pin_assignment,
                                          print_packets,
                                          packet_fn, verbose, test_ctrl)
        self._txen_val = None

    def run(self):
        rand = random.Random()
        last_frame_end_time = None
        nibble = 0
        crumb_index = 0

        xsi = self.xsi
        self.wait(lambda x: xsi.sample_port_pins(self._txen) == 0)
        self._txen_val = 0
        self.wait(lambda x: self._clock.is_low()) # Wait for clock to go low so we can start sampling at the next rising edge
        while True:
            self.wait(lambda x: self._clock.is_high()) # Rising edge
            txen_new = xsi.sample_port_pins(self._txen)
            if txen_new != self._txen_val:
                if txen_new == 1:
                    packet = MiiPacket(rand, blank=True)
                    frame_start_time = self.xsi.get_time()
                    if self._verbose:
                        print(f"Frame start = {frame_start_time/1e6} ns")
                    in_preamble = True
                    crumb_index = 0
                    if last_frame_end_time:
                        ifgap = frame_start_time - last_frame_end_time
                        packet.inter_frame_gap = ifgap
                else:
                    last_frame_end_time = self.xsi.get_time()
                    if self._verbose:
                        print(f"Frame end = {last_frame_end_time/1e6} ns. crumb_index = {crumb_index}")
                    packet.complete()

                    if self._print_packets:
                        sys.stdout.write(packet.dump())

                    if self._packet_fn:
                        if self._test_ctrl:
                            self._packet_fn(packet, self, self._test_ctrl)
                        else:
                            self._packet_fn(packet, self)

                    # Perform packet checks
                    packet.check(self._clock)

                self._txen_val = txen_new

            if self._txen_val == 1: # Sample data
                if self._txd_port_width == 4:
                    if self._txd_4b_port_pin_assignment == "lower_2b":
                        crumb = xsi.sample_port_pins(self._txd[0]) & 0x3
                        #print(f"crumb = {crumb}")
                    else:
                        crumb = (xsi.sample_port_pins(self._txd[0]) >> 2) & 0x3
                else: # 2, 1bit ports
                    cr0 = xsi.sample_port_pins(self._txd[0]) & 0x1
                    cr1 = xsi.sample_port_pins(self._txd[1]) & 0x1
                    crumb = (cr1 << 1) | cr0
                nibble = nibble | (crumb << (crumb_index*2))
                if crumb_index == 1:
                    if self._verbose:
                        print(f"nibble = {nibble:x}")
                    if in_preamble:
                        if nibble == 0xd:
                            packet.set_sfd_nibble(nibble)
                            in_preamble = False
                        else:
                            packet.append_preamble_nibble(nibble)
                    else:
                        packet.append_data_nibble(nibble)
                    nibble = 0

                crumb_index = crumb_index ^ 1
            else:
                if (self._test_ctrl is not None) and (xsi.sample_port_pins(self._test_ctrl) == 1):
                    xsi.terminate()
            self.wait(lambda x: self._clock.is_low())
