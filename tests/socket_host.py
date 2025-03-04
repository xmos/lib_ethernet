# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import subprocess
import platform
from pathlib import Path
import re
from scapy.all import *
from hw_helpers import mii2scapy
from conftest import build_socket_host
import time

pkg_dir = Path(__file__).parent


class SocketHost():
    """
    Class implementing functions to transmit and receive Layer 2 Ethernet packets using a raw socket on Linux.

    This is achieved by executing a C++ compiled application via subprocess.run(), which handles packet transmission and reception.
    """
    def __init__(self, eth_intf, host_mac_addr, dut_mac_addr, verbose=False):
        """
        Constructor for the SocketHost class. Compiles the C++ socket send and receive applications if they are not already compiled.

        Parameters:
        eth_intf (str, eg. "eno1"): ethernet interface on which to send/receive packets. Run the 'ip link' command to get the list of
        available interfaces and choose the relevant one.

        host_mac_addr (str, eg. "11:22:33:44:55:66"): Mac address of the host. Used as source mac address for packets sent by the host.

        dut_mac_addr (str, eg. '11:22:33:44:55:66 aa:bb:cc:dd:ee:ff 00:01:02:03:04:05'): List of mac addresses of the clients running on the device.
        For eg. if the DUT has 3 clients running, dut_mac_addr
        is a string of the form '11:22:33:44:55:66 aa:bb:cc:dd:ee:ff 00:01:02:03:04:05'
        These are used as destination mac addresses when sending packets from the host to the device.

        verbose (bool, optional, default=False): Verbose output when running.
        """
        self.eth_intf = eth_intf
        self.host_mac_addr = host_mac_addr
        self.dut_mac_addr = dut_mac_addr
        self.send_proc = None
        self.num_packets_sent = None
        self.verbose = verbose

        assert platform.system() in ["Linux"], f"Sending using sockets only supported on Linux"
        # build the af_packet_send utility
        socket_host_dir = pkg_dir / "host" / "socket"

        assert socket_host_dir.exists() and socket_host_dir.is_dir(), f"socket_host path {socket_host_dir} invalid"

        self.socket_send_app = socket_host_dir / "build" / "socket_send"
        self.socket_send_recv_app = socket_host_dir / "build" / "socket_send_recv"
        self.socket_recv_app = socket_host_dir / "build" / "socket_recv"

        if not (self.socket_send_app.exists() and self.socket_send_app.exists() and self.socket_recv_app.exists()):
            # Build the xscope controller host application if missing
            build_socket_host()

    def set_cap_net_raw(self, app):
        """
        Grant capability to the application to use raw sockets to send and receive raw sockets
        without requiring root privileges.

        Parameters:
        app (str): application that requires the cap_net_raw capability
        """
        cmd = f"sudo /usr/sbin/setcap cap_net_raw=eip {app}"

        ret = subprocess.run(cmd.split(),
                             capture_output = True,
                             text = True)
        assert ret.returncode == 0, (
            f"{cmd} returned error"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

    def get_num_pkts_sent_from_stdout(self, stdout):
        m = re.search(rf"Socket: Sent (\d+) packets to ethernet interface {self.eth_intf}", stdout)
        assert m, ("Socket send doesn't report num packets sent"
        + f"\nstdout:\n{stdout}")
        return int(m.group(1))

    def send(self, test_duration_s, payload_len="max"):
        """
        Send Layer 2 Ethernet packets over a raw socket. This is a wrapper function that executes the C++ application for sending packets.

        Note that this is a blocking call that returns only after sending the packets.

        Parameters:
        test_duration_s (float): Test duration in seconds
        payload_len (str, optional, one of ["max", "min", "random"], default="max"): The socket send app generates max, min or random sized payload packets depending on this argument.
        """
        assert payload_len in ["max", "min", "random"]
        self.set_cap_net_raw(self.socket_send_app)
        cmd = [self.socket_send_app, self.eth_intf, str(test_duration_s), payload_len, self.host_mac_addr , *(self.dut_mac_addr.split())]
        ret = subprocess.run(cmd,
                             capture_output = True,
                             text = True)

        if self.verbose:
            print(f"After running cmd {' '.join([str(c) for c in cmd])}\n")
            print(f"stdout = {ret.stdout}\n")
            print(f"stderr = {ret.stderr}\n")
        assert ret.returncode == 0, (
            f"Subprocess run of cmd failed: {' '.join([str(c) for c in cmd])}"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )
        return self.get_num_pkts_sent_from_stdout(ret.stdout)


    def send_asynch_start(self, test_duration_s, payload_len="max"):
        """
        Start an asynchronous send of Layer 2 Ethernet packets over a raw socket.
        This is a wrapper function that starts the C++ application for sending packets.

        Unlike send(), this starts the packet send application (subprocess.Popen) and returns.

        Parameters:
        test_duration_s (float): Test duration in seconds
        payload_len (str, optional, one of ["max", "min", "random"], default="max"): The socket send app generates max, min or random sized payload packets depending on this argument.
        """
        assert payload_len in ["max", "min", "random"]
        self.set_cap_net_raw(self.socket_send_app)
        self.num_packets_sent = None
        self.send_cmd = [self.socket_send_app, self.eth_intf, str(test_duration_s), payload_len, self.host_mac_addr , *(self.dut_mac_addr.split())]
        if self.verbose:
            print(f"subprocess Popen: {' '.join([str(c) for c in self.send_cmd])}")

        self.send_proc = subprocess.Popen(
                self.send_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
        # Parse number of sent packets from the stdout

    def send_asynch_check_complete(self):
        """
        Checks whether the Layer 2 packet send application, started in send_asynch_start(), has completed execution.

        If completed, updates self.num_packets_sent with the number of packets sent, extracted from the application's stdout output.

        Returns:
        running (bool): True if still running, False if completed.
        """
        assert self.send_proc
        running = (self.send_proc.poll() == None)
        if not running:
            self.send_proc_stdout, self. send_proc_stderr = self.send_proc.communicate(timeout=60)
            self.send_proc_returncode = self.send_proc.returncode

            if self.verbose:
                print(f"Process ended: {' '.join([str(c) for c in self.send_cmd])}\n")
                print(f"stdout = {self.send_proc_stdout}")
                print(f"stderr = {self.send_proc_stderr}")

            assert self.send_proc_returncode == 0, (
                f"Subprocess run of cmd failed: {' '.join([str(c) for c in self.send_cmd])}"
                + f"\nstdout:\n{self.send_proc_stdout}"
                + f"\nstderr:\n{self. send_proc_stderr}"
            )

            self.num_packets_sent = self.get_num_pkts_sent_from_stdout(self.send_proc_stdout)
            self.send_proc = None
        return running



    def send_recv(self, test_duration_s, payload_len="max"):
        """
        Send and receive Layer 2 Ethernet packets over a raw socket. This wrapper function executes the C++ application to handle both sending and receiving packets simultaneously.

        Note: This is a blocking call. It returns after the sending operation is complete and there has been at least 5 seconds of inactivity following the reception of the last packet.

        Once complete, it parses the number of sent and received packets from the applications stdout output.

        Parameters:
        test_duration_s (float): Test duration in seconds
        payload_len (str, optional, one of ["max", "min", "random"], default="max"): The socket send app generates max, min or random sized payload packets depending on this argument.

        Returns:
        int, int: number of packets sent by the host, number of packets received by the host
        """
        self.set_cap_net_raw(self.socket_send_recv_app)

        cmd = [self.socket_send_recv_app, self.eth_intf, str(test_duration_s), payload_len, self.host_mac_addr , *(self.dut_mac_addr.split())]
        ret = subprocess.run(cmd,
                             capture_output = True,
                             text = True)
        assert ret.returncode == 0, (
            f"Subprocess run of cmd failed: {' '.join([str(c) for c in cmd])}"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

        if self.verbose:
            print(f"After running cmd {' '.join([str(c) for c in cmd])}")
            print(f"stdout = {ret.stdout}")
            print(f"stderr = {ret.stderr}")

        m = re.search(r"Receieved (\d+) packets on ethernet interface", ret.stdout)
        assert m, ("Sniffer doesn't report received packets"
        + f"\nstdout:\n{ret.stdout}"
        + f"\nstderr:\n{ret.stderr}")

        num_packets_sent = self.get_num_pkts_sent_from_stdout(ret.stdout)

        return num_packets_sent, int(m.group(1))

    def recv(self, capture_file):
        """
        Receive Layer 2 Ethernet packets over a raw socket. This is a wrapper function that executes the C++ application for receiving packets.

        Note that this is a blocking call that returns after 5 seconds of inactivity following reception of the last packet.

        Parameters:
        capture_file (str): File in which to capture information about the received packet

        Returns:
        Number of packets received on the ethernet interface
        """
        self.set_cap_net_raw(self.socket_recv_app)
        cmd = [self.socket_recv_app, self.eth_intf, self.host_mac_addr , self.dut_mac_addr, capture_file]
        ret = subprocess.run(cmd,
                             capture_output = True,
                             text = True)
        assert ret.returncode == 0, (
            f"Subprocess run of cmd failed: {' '.join([str(c) for c in cmd])}"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )
        if self.verbose:
            print(f"After running cmd {' '.join([str(c) for c in cmd])}")
            print(f"stdout = {ret.stdout}")
            print(f"stderr = {ret.stderr}")

        m = re.search(r"Receieved (\d+) packets on ethernet interface", ret.stdout)
        assert m, ("Sniffer doesn't report received packets"
        + f"\nstdout:\n{ret.stdout}"
        + f"\nstderr:\n{ret.stderr}")

        return int(m.group(1))

    def recv_asynch_start(self, capture_file):
        """
        Start an asynchronous receive of Layer 2 Ethernet packets over a raw socket.
        This is a wrapper function that starts the C++ application for receiving packets.

        Unlike recv(), this starts the packet receive application (subprocess.Popen) and returns.

        Parameters:
        capture_file (str): File in which to capture information about the received packet
        """
        self.set_cap_net_raw(self.socket_recv_app)
        self.recv_cmd = [self.socket_recv_app, self.eth_intf, self.host_mac_addr , self.dut_mac_addr, capture_file]
        if self.verbose:
            print(f"subprocess Popen: {' '.join([str(c) for c in self.recv_cmd])}")
        self.recv_proc = subprocess.Popen(self.recv_cmd,
                                            stdout=subprocess.PIPE,
                                            stderr=subprocess.PIPE,
                                            text=True)

    def recv_asynch_wait_complete(self):
        """
        Wait for the Layer 2 packet receive application, started in recv_asynch_start(), to complete execution.

        When completed, return the number of received packets, extracted from the host application's stdout output.

        Returns:
        int: Number of packets received.
        """
        assert self.recv_proc
        while True:
            running = (self.recv_proc.poll() == None)
            if not running:
                self.recv_proc_stdout, self.recv_proc_stderr = self.recv_proc.communicate(timeout=60)
                self.recv_proc_returncode = self.recv_proc.returncode
                assert self.recv_proc_returncode == 0, (
                    f"Subprocess run of cmd failed: {' '.join([str(c) for c in self.recv_cmd])}"
                    + f"\nstdout:\n{self.recv_proc_stdout}"
                    + f"\nstderr:\n{self.recv_proc_stderr}"
                )

                if self.verbose:
                    print(f"Process ended: {' '.join([str(c) for c in self.recv_cmd])}\n")
                    print(f"stderr = {self.recv_proc_stderr}")
                    print(f"stdout = {self.recv_proc_stdout}")

                m = re.search(r"Receieved (\d+) packets on ethernet interface", self.recv_proc_stdout)
                assert m, ("Sniffer doesn't report received packets"
                + f"\nstdout:\n{self.recv_proc_stdout}"
                + f"\nstderr:\n{self.recv_proc_stderr}")

                return int(m.group(1))
            time.sleep(0.1)


# Send the same packet in a loop
def scapy_send_l2_pkt_loop(intf, packet, loop_count, time_container):
    """
    Continuously send the same packet from the host to the device in a loop using Scapy.

    Parameters:
    intf (str, eg. "eno1"): network interface name. Run 'ip link' to check the list of available interfaces
    packet (MiiPacket): Packet in the form of a MiiPacket object
    loop_count (int): The number of times to send the same packet.
    time_container (list): List in which to append the send time
    """
    frame = mii2scapy(packet)
    # Send over ethernet
    start = time.perf_counter()
    sendp(frame, iface=intf, count=loop_count, verbose=False, realtime=True)
    end = time.perf_counter()
    time_container.append(end-start)



def scapy_send_l2_pkt_sequence(intf, packets, time_container):
    """
    Send a sequence of packets from the host to the device using Scapy.

    Parameters:
    intf (str, eg. "eno1"): network interface name. Run 'ip link' to check the list of available interfaces
    packet (list of MiiPacket objects): Packet list in the form of a MiiPacket object list
    time_container (list): List in which to append the send time
    """
    frames = mii2scapy(packets)
    start = time.perf_counter()
    sendp(frames, iface=intf, verbose=False, realtime=True)
    end = time.perf_counter()
    time_container.append(end-start)

# To test the host app standalone
from xscope_host import XscopeControl
if __name__ == "__main__":
    xscope_host = XscopeControl("localhost", "12340", verbose=True)
    xscope_host.xscope_controller_cmd_connect()
    xscope_host.xscope_controller_cmd_set_dut_tx_packets(0, 10000, 1500)
    xscope_host.xscope_controller_cmd_set_dut_tx_packets(1, 25000000, 1500)
