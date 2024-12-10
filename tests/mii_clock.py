# Copyright 2014-2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import Pyxsim as px
import sys
import zlib

class Clock(px.SimThread):

    # Use the values that need to be presented in the RGMII data pins when DV inactive
    (CLK_125MHz, CLK_25MHz, CLK_2_5MHz, CLK_50MHz) = (0x4, 0x2, 0x0, 0x1)

    # ifg = inter frame gap
    # bit_time = time per physical layer bit in femtoseconds

    def __init__(self, port, clk):
        self._running = True
        self._clk = clk
        sim_clock_rate = px.Xsi.get_xsi_tick_freq_hz() # xsim uses femotseconds
        if clk == self.CLK_125MHz:
            self._period = float(sim_clock_rate) / 125e6 # xsi ticks per clock cycle
            self._name = '125Mhz'
            # 8 bits per clock period at 125MHz = 1000 Mbps. bit time = 1/1000Mbps = 1e-9 (or 1ns) seconds per bit
            self._clock_cycle_to_bit_time_ratio = 8 # 1 clock cycle is 8 times a bit time
        elif clk == self.CLK_25MHz:
            self._period = float(sim_clock_rate) / 25e6
            self._name = '25Mhz'
            # 4 bits per clock at 25MHz = 100Mbps. bit time = 1e-8 (or 10ns) seconds per bit
            self._clock_cycle_to_bit_time_ratio = 4 # 1 clock cycle is 4 times a bit time
        elif clk == self.CLK_2_5MHz:
            self._period = float(sim_clock_rate) / 2.5e6
            self._name = '2.5Mhz'
            # 4 bits per clock at 2.5MHz = 10Mbps. bit time = 1e-7 (or 100ns) seconds per bit
            self._clock_cycle_to_bit_time_ratio = 4 # 1 clock cycle is 4 times a bit time
        elif clk == self.CLK_50MHz:
            self._period = float(sim_clock_rate) / 50e6 # xsi ticks per clock cycle
            self._name = '50MHz'
            # 2 bits per clock at 50MHz = 100Mbps. bit time = 1e-8 (or 10ns) seconds per bit
            self._clock_cycle_to_bit_time_ratio = 2 # 1 clock cycle is 2 times a bit time


        self._bit_time = self._period / self._clock_cycle_to_bit_time_ratio # xsim ticks per bit
        self._min_ifg = 96 * self._bit_time
        self._min_ifg_clock_cycles = 96 / self._clock_cycle_to_bit_time_ratio # Counting IFG time in no. of ethernet clock cycles

        self._val = 0
        self._port = port

    def run(self):
        while True:
            self.wait_until(self.xsi.get_time() + self._period/2)
            self._val = 1 - self._val

            if self._running:
                self.xsi.drive_port_pins(self._port, self._val)

    def val(self):
        return self._val

    def is_high(self):
        return (self._val == 1)

    def is_low(self):
        return (self._val == 0)

    def get_rate(self):
        return self._clk

    def get_name(self):
        return self._name

    def get_min_ifg(self):
        return self._min_ifg

    def get_bit_time(self):
        return self._bit_time

    def get_clock_cycle_to_bit_time_ratio(self):
        return self._clock_cycle_to_bit_time_ratio

    def get_min_ifg_clock_cycles(self):
        return self._min_ifg_clock_cycles

    def stop(self):
        self._running = False

    def start(self):
        self._running = True
