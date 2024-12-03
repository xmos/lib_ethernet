# Copyright 2024 XMOS LIMITED.
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
                 initial_delay, verbose,
                 test_ctrl, do_timeout, complete_fn, expect_loopback, dut_exit_time):
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
        self._initial_delay = initial_delay
        self._verbose = verbose
        self._do_timeout = do_timeout
        self._complete_fn = complete_fn
        self._expect_loopback = expect_loopback
        self._dut_exit_time = dut_exit_time
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

class RMiiTransmitter(RMiiTxPhy):

    def __init__(self, rxd, rxdv, rxer, clock,
                 rxd_4b_port_pin_assignment="lower_2b",
                 initial_delay=(85 * px.Xsi.get_xsi_tick_freq_hz())/1e6, verbose=False, test_ctrl=None,
                 do_timeout=True, complete_fn=None, expect_loopback=True,
                 dut_exit_time=(25 * px.Xsi.get_xsi_tick_freq_hz())/1e6):
        super(RMiiTransmitter, self).__init__('rmii', rxd, rxdv, rxer, clock,
                                             rxd_4b_port_pin_assignment,
                                             initial_delay, verbose, test_ctrl,
                                             do_timeout, complete_fn, expect_loopback,
                                             dut_exit_time)

    def run(self):
        xsi = self.xsi

        self.start_test()

        for i,packet in enumerate(self._packets):
            print(f"Packet {i}")
            error_nibbles = packet.get_error_nibbles()

            self.wait_until(xsi.get_time() + packet.inter_frame_gap)

            if self._verbose:
                print(f"Sending packet {i}: {packet}")
                sys.stdout.write(packet.dump())

            for (i, nibble) in enumerate(packet.get_nibbles()):
                for j in range(2): # Drive 2 bits every high -> low clock edge. We have a nibble so run this loop twice
                    crumb = (nibble >> (j*2)) & 0x3
                    self.wait(lambda x: self._clock.is_low())
                    xsi.drive_port_pins(self._rxdv, 1)
                    #print(f"{self._rxd_port_width}, {self._rxd_4b_port_pin_assignment}, {self._rxd[0]}")
                    #if j == 0:
                    #    print(f"nibble = {nibble:x}")

                    if self._rxd_port_width == 4:
                        if self._rxd_4b_port_pin_assignment == "lower_2b":
                            xsi.drive_port_pins(self._rxd[0], crumb)
                            #print(f"crumb = {crumb:x}")
                        else:
                            xsi.drive_port_pins(self._rxd[0], (crumb << 2))
                    else: # 2, 1bit ports
                        xsi.drive_port_pins(self._rxd[0], crumb & 0x1)
                        xsi.drive_port_pins(self._rxd[1], (crumb >> 1) & 0x1)

                    # Signal an error if required
                    if i in error_nibbles:
                        xsi.drive_port_pins(self._rxer, 1)
                    else:
                        xsi.drive_port_pins(self._rxer, 0)

                    self.wait(lambda x: self._clock.is_high())

            self.wait(lambda x: self._clock.is_low())
            xsi.drive_port_pins(self._rxdv, 0)
            xsi.drive_port_pins(self._rxer, 0)

            if self._verbose:
                print("Sent")

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
        print(f"self._txd = {self._txd}, self._txd_port_width = {self._txd_port_width}, self._txd_4b_port_pin_assignment = {self._txd_4b_port_pin_assignment}")

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

                if (xsi.sample_port_pins(self._txen) == 0 and
                      xsi.sample_port_pins(self._test_ctrl) == 1):
                    xsi.terminate()

            print("START")
            # Start with a blank packet to ensure they are filled in by the receiver
            packet = MiiPacket(rand, blank=True)

            frame_start_time = self.xsi.get_time()
            in_preamble = True
            start = True

            if last_frame_end_time:
                ifgap = frame_start_time - last_frame_end_time
                packet.inter_frame_gap = ifgap

            while True:
                done = 0
                nibble = 0
                for j in range(2):
                    # Wait for a falling clock edge or enable low
                    self.wait(lambda x: self._clock.is_high() or \
                                    xsi.sample_port_pins(self._txen) == 0)
                    if start:
                        print(f"Frame start = {self.xsi.get_time()/1e6} ns")
                        start = False

                    if xsi.sample_port_pins(self._txen) == 0:
                        last_frame_end_time = self.xsi.get_time()
                        print(f"Frame end = {last_frame_end_time/1e6} ns")
                        assert j == 0
                        done = 1
                        break

                    if self._txd_port_width == 4:
                        if self._txd_4b_port_pin_assignment == "lower_2b":
                            crumb = xsi.sample_port_pins(self._txd[0]) & 0x3
                            #print(f"crumb = {crumb}")
                        else:
                            crumb = (xsi.sample_port_pins(self._txd[0]) >> 2) & 0x3
                    else: # 2, 1bit ports
                        cr0 = xsi.sample_port_pins(self._txd[0]) & 0x1
                        cr1 = xsi.sample_port_pins(self._txd[1]) & 0x1
                        crumb = (cr1 << 1) & cr0
                    nibble = nibble | (crumb << (j*2))

                    if j == 1:
                        #print(f"nibble = {nibble:x}")
                        if in_preamble:
                            if nibble == 0xd:
                                packet.set_sfd_nibble(nibble)
                                in_preamble = False
                            else:
                                packet.append_preamble_nibble(nibble)
                        else:
                            packet.append_data_nibble(nibble)

                    self.wait(lambda x: self._clock.is_low())
                if done:
                    break

            print("DONE")
            packet.complete()

            if self._print_packets:
                sys.stdout.write(packet.dump())

            if self._packet_fn:
                self._packet_fn(packet, self)

            # Perform packet checks
            packet.check(self._clock)
