# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
from scapy.all import *
from pathlib import Path
from hw_helpers import get_mac_address, hw_eth_debugger
import pytest
from xcore_app_control import XcoreAppControl
from socket_host import SocketHost
import platform


pkg_dir = Path(__file__).parent

@pytest.mark.parametrize('send_method', ['socket'])
def test_hw_restart(request, send_method):
    """
    Test exiting and restarting the Mac threads.

    This test sends the restart command to the device over xscope control which causes the MAC
    and client loopback rx thread to exit and start again.

    After restarting the test checks that no packets get looped back from the device since the MAC address filters
    that were set in the device prior to restart should now have got reset. This is an indication that
    the MAC actually did restart.
    Once the Mac address filters are set in the device, loopback is again tested and the device is expected to
    successfully loopback packets now.

    The above sequence is repeated 'num_restarts' times.
    """
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    eth_intf = request.config.getoption("--eth-intf")
    assert eth_intf != None, "Error: Specify a valid ethernet interface name on which to send traffic"

    no_debugger = request.config.getoption("--no-debugger")

    phy = request.config.getoption("--phy")

    verbose = False
    test_duration_s = 5.0
    payload_len = 'max'
    num_restarts = 4

    host_mac_address_str = get_mac_address(eth_intf)
    assert host_mac_address_str, f"get_mac_address() couldn't find mac address for interface {eth_intf}"
    print(f"host_mac_address = {host_mac_address_str}")

    dut_mac_address_str = "00:11:22:33:44:55"
    print(f"dut_mac_address = {dut_mac_address_str}")


    print(f"Going to test {test_duration_s} seconds of packets")

    if send_method == "socket":
        assert platform.system() in ["Linux"], f"Sending using sockets only supported on Linux"
        socket_host = SocketHost(eth_intf, host_mac_address_str, dut_mac_address_str, verbose=verbose)
    else:
        assert False, f"Invalid send_method {send_method}"


    xe_name = pkg_dir / "hw_test_rmii_loopback" / "bin" / f"loopback_{phy}" / f"hw_test_rmii_loopback_{phy}.xe"
    with XcoreAppControl(adapter_id, xe_name, verbose=verbose) as xcoreapp, hw_eth_debugger() as dbg:
        print("Wait for DUT to be ready")
        if not no_debugger:
            if dbg.wait_for_links_up():
                print("Links up")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()

        print("Set DUT Mac address")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(0, dut_mac_address_str)

        if send_method == "socket":
            num_packets_sent, host_received_packets = socket_host.send_recv(test_duration_s)
            if host_received_packets != num_packets_sent:
                print(f"ERROR: Host received back fewer than it sent. Sent {num_packets_sent}, received back {host_received_packets}")
                stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()
                print("shutdown stdout:\n")
                print(stdout)
                assert False

        for _ in range(num_restarts):
            # restart the mac
            print("Restart DUT Mac")
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_restart_dut_mac()

            # wait to connect again
            print("Connect to the DUT again")
            if not no_debugger:
                if dbg.wait_for_links_up():
                    print("Links up")
            stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()

            if send_method == "socket":
                num_packets_sent, host_received_packets = socket_host.send_recv(test_duration_s)
                if host_received_packets != 0:
                    print(f"After mac restart and before setting macaddr filters, host expected to receive 0 packets. Received {host_received_packets} packets instead")
                    stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()
                    print("shutdown stdout:\n")
                    print(stdout)
                    assert False

            stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(0, dut_mac_address_str)

            # Now the RX client should receive packets
            if send_method == "socket":
                num_packets_sent, host_received_packets = socket_host.send_recv(test_duration_s)
                if host_received_packets != num_packets_sent:
                    print(f"ERROR: Host received back fewer than it sent. Sent {num_packets_sent}, received back {host_received_packets}")
                    stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()
                    print("shutdown stdout:\n")
                    print(stdout)
                    assert False

        print("Retrive status and shutdown DUT")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()

        print("Terminating!!!")


