import subprocess
import platform
from pathlib import Path
import re
from scapy.all import *
from hw_helpers import mii2scapy
from hardware_test_tools.XcoreApp import XcoreApp
from conftest import build_xcope_control_host, build_socket_host
import time
from enum import Enum, auto
from xscope import Endpoint, QueueConsumer

pkg_dir = Path(__file__).parent

class XscopeCommands(Enum):
    CMD_DEVICE_SHUTDOWN = auto()
    CMD_SET_DEVICE_MACADDR = auto()
    CMD_SET_HOST_MACADDR = auto()
    CMD_HOST_SET_DUT_TX_PACKETS = auto()
    CMD_SET_DUT_RECEIVE = auto()
    CMD_DEVICE_CONNECT = auto()
    CMD_EXIT_DEVICE_MAC = auto()

class XscopeControl():
    def __init__(self, host, port, timeout=30, verbose=False):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.verbose = verbose

    def xscope_controller_do_command(self, cmds):
        """
        Runs the xscope host app to connect to the DUT and execute a command over xscope port

        Parameters:
        xscope_controller: xscope host application binary
        cmds (list): byte list containing the command + arguments for the command that needs to be executed
        timeout: timeout in seconds for when not able to communicate with the device

        Returns:
        stdout and stderr from running the host application
        """
        ep = Endpoint()
        probe = QueueConsumer(ep, "command_ack")

        if ep.connect(hostname=self.host, port=self.port):
            print("Xscope Host app failed to connect")
            assert False
        if self.verbose:
            print(f"Sending {cmds} bytes to the device over xscope")
        ep.publish(bytes(cmds))
        ack = probe.next()
        if self.verbose:
            print(f"Received ack {ack}")

        device_stdout = ep._captured_output.getvalue() # stdout from the device
        if self.verbose:
            print("stdout from the device:")
            print(device_stdout)

        ep.disconnect()


        return device_stdout


    def xscope_controller_cmd_connect(self):
        """
        Run command to ensure that the xcore device is setup and ready to communicate via ethernet

        Returns:
        stdout and stderr from running the host application
        """
        return self.xscope_controller_do_command([XscopeCommands['CMD_DEVICE_CONNECT'].value])


    def xscope_controller_cmd_shutdown(self):
        """
        Run command to shutdown the xcore application threads and exit gracefully

        Returns:
        stdout and stderr from running the host application
        """
        return self.xscope_controller_do_command([XscopeCommands['CMD_DEVICE_SHUTDOWN'].value])

    def xscope_controller_cmd_set_dut_macaddr(self, client_index, mac_addr):
        """
        Run command to set the src mac address of a client running on the DUT.

        Parameters:
        client_index: index of the client.
        mac_addr: mac address (example, 11:e0:24:df:33:66)

        Returns:
        stdout and stderr from running the host application
        """
        mac_addr_bytes = [int(i, 16) for i in mac_addr.split(":")]
        cmd_plus_args = [XscopeCommands['CMD_SET_DEVICE_MACADDR'].value, client_index]
        cmd_plus_args.extend(mac_addr_bytes)
        return self.xscope_controller_do_command(cmd_plus_args)

    def xscope_controller_cmd_set_host_macaddr(self, mac_addr):
        """
        Run command to inform the DUT of the host's mac address. This is required so that a TX client running on the DUT knows the destination
        mac address for the ethernet packets it is sending.

        Parameters:
        mac_addr: mac address (example, 11:e0:24:df:33:66)

        Returns:
        stdout and stderr from running the host application
        """
        mac_addr_bytes = [int(i, 16) for i in mac_addr.split(":")]
        cmd_plus_args = [XscopeCommands['CMD_SET_HOST_MACADDR'].value]
        cmd_plus_args.extend(mac_addr_bytes)
        return self.xscope_controller_do_command(cmd_plus_args)

    def xscope_controller_cmd_set_dut_tx_packets(self, client_index, arg1, arg2):
        """
        Run command to inform the TX clients on the DUT the number of packets and length of each packet that it needs to transmit

        Parameters:
        arg1: number of packets to send for LP thread. qav bw in bps for HP thread
        arg2: packet payload length in bytes

        Returns:
        stdout and stderr from running the host application
        """
        cmd_plus_args = [XscopeCommands['CMD_HOST_SET_DUT_TX_PACKETS'].value]
        for a in [client_index, arg1, arg2]: # client_index, arg1 and arg2 are int32
            bytes_to_append = [(a >> (8 * i)) & 0xFF for i in range(4)]
            cmd_plus_args.extend(bytes_to_append)
        return self.xscope_controller_do_command(cmd_plus_args)


    def xscope_controller_cmd_set_dut_receive(self, client_index, recv_flag):
        """
        Run command to a given RX client on the DUT to start or stop receiving packets.

        Parameters:
        client_index: RX client index on the DUT
        recv_flag: Flag indicating whether to receive (1) or not receive (0) the packet

        Returns:
        stdout and stderr from running the host application
        """
        cmd_plus_args = [XscopeCommands['CMD_SET_DUT_RECEIVE'].value, client_index, recv_flag]
        return self.xscope_controller_do_command(cmd_plus_args)

    def xscope_controller_cmd_restart_dut_mac(self):
        """
        Run command to restart the DUT Mac.

        Returns:
        stdout and stderr from running the host application
        """
        return self.xscope_controller_do_command([XscopeCommands['CMD_EXIT_DEVICE_MAC'].value])

class XcoreAppControl(XcoreApp):
    """
    Class containing host side functions used for communicating with the XMOS device (DUT) over xscope port.
    These are wrapper functions that run the C++ xscope host application which actually communicates with the DUT over xscope.
    It is derived from XcoreApp which xruns the DUT application with the --xscope-port option.
    """
    def __init__(self, adapter_id, xe_name, attach=None, verbose=False):
        """
        Initialise the XcoreAppControl class. This compiles the xscope host application (host/xscope_controller).
        It also calls init for the base class XcoreApp, which xruns the XMOS device application (DUT) such that the host app
        can communicate to it over xscope port

        Parameter: compiled DUT application binary
        adapter-id: adapter ID of the XMOS device
        """
        self.verbose = verbose
        assert platform.system() in ["Darwin", "Linux"]
        super().__init__(xe_name, adapter_id, attach=attach)
        assert self.attach == "xscope_app"
        self.xscope_host = None

    def __enter__(self):
        super().__enter__()
        # self.xscope_port is only set in XcoreApp.__enter__(), so xscope_host can only be created now and not in XcoreAppControl's constructor
        self.xscope_host = XscopeControl("localhost", f"{self.xscope_port}", verbose=self.verbose)
        return self


class SocketHost():
    """
    Class containing functions that send and receive L2 ethernet packets over a raw socket.
    """
    def __init__(self, eth_intf, host_mac_addr, dut_mac_addr, verbose=False):
        """
        Constructor for the SocketHost class. It compiles the C++ socket send and receive applications.

        Parameters:
        eth_intf: ethernet interface on which to send/receive packets
        host_mac_addr: Mac address of the host. Used as src mac address for packets sent by the host. String of the form '11:22:33:44:55:66'
        dut_mac_addr: List of mac addresses of the client running on the dut. For example, if the DUT has 3 client running, dut_mac_addr
        is a string of the form '11:22:33:44:55:66 aa:bb:cc:dd:ee:ff 00:01:02:03:04:05'
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
        Send L2 packets over a raw socket. This is a wrapper functin that runs the C++ socket send packets application.

        Parameters:
        test_duration_s: Test duration in seconds
        payload_len: string. One of 'max', 'min' or 'random'. The socket send app generates max, min or random sized payload packets depending on this argument.
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


    def send_non_blocking(self, test_duration_s, payload_len="max"):
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

    def send_in_progress(self):
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
        self.set_cap_net_raw(self.socket_recv_app)
        self.recv_cmd = [self.socket_recv_app, self.eth_intf, self.host_mac_addr , self.dut_mac_addr, capture_file]
        if self.verbose:
            print(f"subprocess Popen: {' '.join([str(c) for c in self.recv_cmd])}")
        self.recv_proc = subprocess.Popen(self.recv_cmd,
                                            stdout=subprocess.PIPE,
                                            stderr=subprocess.PIPE,
                                            text=True)

    def recv_asynch_wait_complete(self):
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
def scapy_send_l2_pkts_loop(intf, packet, loop_count, time_container):
    frame = mii2scapy(packet)
    # Send over ethernet
    start = time.perf_counter()
    sendp(frame, iface=intf, count=loop_count, verbose=False, realtime=True)
    end = time.perf_counter()
    time_container.append(end-start)



def scapy_send_l2_pkt_sequence(intf, packets, time_container):
    frames = mii2scapy(packets)
    start = time.perf_counter()
    sendp(frames, iface=intf, verbose=False, realtime=True)
    end = time.perf_counter()
    time_container.append(end-start)

# To test the host app standalone
if __name__ == "__main__":
    xscope_controller_cmd_connect()
    xscope_controller_cmd_set_dut_tx_packets(0, 10000, 1500)
    xscope_controller_cmd_set_dut_tx_packets(1, 25000000, 1500)



