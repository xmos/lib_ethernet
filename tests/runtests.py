#!/usr/bin/env python
import xmostest

if __name__ == "__main__":
    xmostest.init()

    xmostest.register_group("lib_ethernet",
                            "basic_tests",
                            "Ethernet basic tests",
    """
Tests are performed by running the ethernet library connected to a
simulator model (written as a python plugin to xsim). Basic functioanlity is tested such as basic sending and receiving of packets, rejection of bad packets, interframe gap testing.
""")

    xmostest.build('test_rx')
    xmostest.build('test_tx')
    xmostest.build('test_etype_filter')
    xmostest.build('test_time_tx')
    xmostest.build('test_time_rx')

    xmostest.runtests()

    xmostest.finish()
