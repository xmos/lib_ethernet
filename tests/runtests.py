#!/usr/bin/env python
import xmostest
import argparse

import helpers

if __name__ == "__main__":
    global trace
    argparser = argparse.ArgumentParser(description="XMOS lib_ethernet tests")
    argparser.add_argument('--trace', action='store_true', help='Run tests with simulator and VCD traces')
    argparser.add_argument('--phy', choices=['mii', 'rgmii'], type=str, help='Run tests only on specified PHY')
    argparser.add_argument('--arch', choices=['xs1', 'xs2'], type=str, help='Run tests only on specified xcore architecture')
    argparser.add_argument('--clk', choices=['25Mhz', '125Mhz'], type=str, help='Run tests only at specified clock speed')
    argparser.add_argument('--mac', choices=['rt', 'rt_hp', 'standard'], type=str, help='Run tests only on specified MAC')
    argparser.add_argument('--seed', type=int, help='The seed', default=None)
    argparser.add_argument('--verbose', action='store_true', help='Enable verbose tracing in the phys')

    argparser.add_argument('--num-packets', type=int, help='Number of packets in the test', default='100')
    argparser.add_argument('--weight-hp', type=int, help='Weight of high priority traffic', default='50')
    argparser.add_argument('--weight-lp', type=int, help='Weight of low priority traffic', default='25')
    argparser.add_argument('--weight-other', type=int, help='Weight of other (dropped) traffic', default='25')
    argparser.add_argument('--data-len-min', type=int, help='Minimum packet data bytes', default='46')
    argparser.add_argument('--data-len-max', type=int, help='Maximum packet data bytes', default='500')
    argparser.add_argument('--weight-tagged', type=int, help='Weight of VLAN tagged traffic', default='50')
    argparser.add_argument('--weight-untagged', type=int, help='Weight of non-VLAN tagged traffic', default='50')
    argparser.add_argument('--max-hp-mbps', type=int, help='The maximum megabits per second', default='1000')

    helpers.args = xmostest.init(argparser)

    xmostest.register_group("lib_ethernet",
                            "basic_tests",
                            "Ethernet basic tests",
    """
Tests are performed by running the ethernet library connected to a
simulator model (written as a python plugin to xsim). Basic functioanlity is tested such as basic sending and receiving of packets, rejection of bad packets, interframe gap testing.
""")

    xmostest.runtests()

    xmostest.finish()
