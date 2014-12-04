import xmostest
import sys
import zlib

class Clock(xmostest.SimThread):

    # Use the values that need to be presented in the RGMII data pins when DV inactive
    (CLK_125MHz, CLK_25MHz, CLK_2_5MHz) = (0x4, 0x2, 0x0)

    def __init__(self, port, clk):
        self._clk = clk
        if clk == self.CLK_125MHz:
            self._period = float(1000000000) / 125000000
            self._name = '1Gbs'
            self._min_ifg = 96
        elif clk == self.CLK_25MHz:
            self._period = float(1000000000) / 25000000
            self._name = '100Mbs'
            self._min_ifg = 960
        elif clk == self.CLK_2_5MHz:
            self._period = float(1000000000) / 2500000
            self._name = '10Mbs'
            self._min_ifg = 9600
        self._val = 0
        self._port = port

    def run(self):
        while True:
            self.wait_until(self.xsi.get_time() + self._period/2)
            self._val = 1 - self._val
            self.xsi.drive_port_pins(self._port, self._val)

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
