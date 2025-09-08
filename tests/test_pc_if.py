# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import pytest
import subprocess


def test_pc_if(request):
    """
    This tests the agent running the tests to check that the interface settings are correct.

    Using subprocess to run 'ip a | grep <phy>:' to get the interface details and check that
    1. The interface is UP
    2. The interface is using pfifo_fast qdisc
    """

    intf = request.config.getoption("--eth-intf")

    ip_cmd = ["ip", "a", "|", "grep"]
    ip_cmd.append(intf)

    ip_cmd_str = ' '.join(ip_cmd)
    # Append ':' to the interface name to avoid duplicate matches, as it expects something similar to,
    # "3: eno1: <BROADCAST,MULTICAST,UP,LOWER_UP> ..."
    ip_cmd_str += ":"

    result = subprocess.run(ip_cmd_str, shell=True, capture_output=True)
    ip_string = result.stdout.decode('utf-8').strip()

    # Check that the command was successful
    assert result.returncode == 0, "Command failed to return a line"

    # Is interface UP?
    assert "UP" in ip_string

    # Is interface using pfifo_fast qdisc?
    assert "qdisc" in ip_string
    assert "qdisc pfifo_fast" in ip_string
