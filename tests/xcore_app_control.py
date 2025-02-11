import subprocess
import platform
from pathlib import Path
import re
from scapy.all import *
from hw_helpers import mii2scapy
from hardware_test_tools.XcoreApp import XcoreApp

pkg_dir = Path(__file__).parent

class XcoreAppControl(XcoreApp):
    """
    Class containing host side functions used for communicating with the XMOS device (DUT) over xscope port.
    These are wrapper functions that run the C++ xscope host application which actually communicates with the DUT over xscope.
    It is derived from XcoreApp which xruns the DUT application with the --xscope-port option.
    """
    def __init__(self, adapter_id, xe_name, attach=None):
        """
        Initialise the XcoreAppControl class. This compiles the xscope host application (host/xscope_controller).
        It also calls init for the base class XcoreApp, which xruns the XMOS device application (DUT) such that the host app
        can communicate to it over xscope port

        Parameter: compiled DUT application binary
        adapter-id: adapter ID of the XMOS device
        """
        assert platform.system() in ["Darwin", "Linux"]
        super().__init__(xe_name, adapter_id, attach=attach)

        assert self.attach == "xscope_app"

        xscope_controller_dir = pkg_dir / "host"/ "xscope_controller"

        assert xscope_controller_dir.exists() and xscope_controller_dir.is_dir(), f"xscope_controller path {xscope_controller_dir} invalid"

        # Build the xscope controller host application
        ret = subprocess.run(["cmake", "-B", "build"],
                            capture_output=True,
                            text=True,
                            cwd=xscope_controller_dir)

        assert ret.returncode == 0, (
            f"xscope controller cmake command failed"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

        ret = subprocess.run(["make", "-C", "build"],
                            capture_output=True,
                            text=True,
                            cwd=xscope_controller_dir)

        assert ret.returncode == 0, (
            f"xscope controller make command failed"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

        self.xscope_controller_app = xscope_controller_dir / "build" / "xscope_controller"
        assert self.xscope_controller_app.exists(), f"xscope_controller not present at {self.xscope_controller_app}"


    def xscope_controller_do_command(self, xscope_controller, cmds, timeout):
        """
        Runs the xscope host app to connect to the DUT and execute a command over xscope port

        Parameters:
        xscope_controller: xscope host application binary
        cmds: command + arguments for the command that needs to be executed
        timeout: timeout in seconds for when not able to communicate with the device

        Returns:
        stdout and stderr from running the host application
        """
        ret = subprocess.run(
            [xscope_controller, "localhost", f"{self.xscope_port}", *cmds],
            capture_output=True,
            text=True,
            timeout=timeout
        )
        assert ret.returncode == 0, (
            f"xscope controller command failed on port {self.xscope_port} with commands {cmds}"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

        return ret.stdout, ret.stderr


    def xscope_controller_cmd_connect(self, timeout=30):
        """
        Run command to ensure that the xcore device is setup and ready to communicate via ethernet

        Returns:
        stdout and stderr from running the host application
        """
        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, ["connect"], timeout)
        return stdout, stderr

    def xscope_controller_cmd_shutdown(self, timeout=30):
        """
        Run command to shutdown the xcore application threads and exit gracefully

        Returns:
        stdout and stderr from running the host application
        """
        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, ["shutdown"], timeout)
        return stdout, stderr

    def xscope_controller_cmd_set_dut_macaddr(self, client_index, mac_addr, timeout=30):
        """
        Run command to set the src mac address of a client running on the DUT.

        Parameters:
        client_index: index of the client.
        mac_addr: mac address (example, 11:e0:24:df:33:66)

        Returns:
        stdout and stderr from running the host application
        """
        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, ["set_dut_macaddr", str(client_index), str(mac_addr)], timeout)
        return stdout, stderr

    def xscope_controller_cmd_set_host_macaddr(self, mac_addr, timeout=30):
        """
        Run command to inform the DUT of the host's mac address. This is required so that a TX client running on the DUT knows the destination
        mac address for the ethernet packets it is sending.

        Parameters:
        mac_addr: mac address (example, 11:e0:24:df:33:66)

        Returns:
        stdout and stderr from running the host application
        """

        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, ["set_host_macaddr", str(mac_addr)], timeout)
        return stdout, stderr

    def xscope_controller_cmd_set_dut_tx_packets(self, client_index, arg1, arg2, timeout=30):
        """
        Run command to inform the TX clients on the DUT the number of packets and length of each packet that it needs to transmit

        Parameters:
        arg1: number of packets to send for LP thread. qav bw in bps for HP thread
        arg2: packet payload length in bytes

        Returns:
        stdout and stderr from running the host application
        """
        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, ["set_dut_tx_packets", str(client_index), str(arg1), str(arg2)], timeout)
        return stdout, stderr

    def xscope_controller_cmd_set_dut_receive(self, client_index, recv_flag, timeout=30):
        """
        Run command to a given RX client on the DUT to start or stop receiving packets.

        Parameters:
        client_index: RX client index on the DUT
        recv_flag: Flag indicating whether to receive (1) or not receive (0) the packet

        Returns:
        stdout and stderr from running the host application
        """
        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, ["set_dut_receive", str(client_index), str(recv_flag)], timeout)
        return stdout, stderr


class SocketHost():
    """
    Class containing functions that send and receive L2 ethernet packets over a raw socket.
    """
    def __init__(self, eth_intf, host_mac_addr, dut_mac_addr):
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

        assert platform.system() in ["Linux"], f"Sending using sockets only supported on Linux"
        # build the af_packet_send utility
        socket_host_dir = pkg_dir / "host" / "socket"
         # Build the xscope controller host application
        ret = subprocess.run(["cmake", "-B", "build"],
                            capture_output=True,
                            text=True,
                            cwd=socket_host_dir)

        assert ret.returncode == 0, (
            f"socket host cmake command failed"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

        ret = subprocess.run(["make", "-C", "build"],
                            capture_output=True,
                            text=True,
                            cwd=socket_host_dir)

        assert ret.returncode == 0, (
            f"socket host make command failed"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

        self.socket_send_app = socket_host_dir / "build" / "socket_send"
        assert self.socket_send_app.exists(), f"socket host app {self.socket_send_app} doesn't exist"

        self.socket_send_recv_app = socket_host_dir / "build" / "socket_send_recv"
        assert self.socket_send_recv_app.exists(), f"socket host app {self.socket_send_recv_app} doesn't exist"

        self.socket_recv_app = socket_host_dir / "build" / "socket_recv"
        assert self.socket_recv_app.exists(), f"socket host app {self.socket_recv_app} doesn't exist"


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

        ret = subprocess.run([self.socket_send_app, self.eth_intf, str(test_duration_s), payload_len, self.host_mac_addr , *(self.dut_mac_addr.split())],
                             capture_output = True,
                             text = True)
        print(f"stdout = {ret.stdout}")
        assert ret.returncode == 0, (
            f"{self.socket_send_app} returned runtime error"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )
        return self.get_num_pkts_sent_from_stdout(ret.stdout)


    def send_non_blocking(self, test_duration_s, payload_len="max"):
        assert payload_len in ["max", "min", "random"]
        self.set_cap_net_raw(self.socket_send_app)
        self.num_packets_sent = None
        self.send_proc = subprocess.Popen(
                [self.socket_send_app, self.eth_intf, str(test_duration_s), payload_len, self.host_mac_addr , *(self.dut_mac_addr.split())],
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
            assert self.send_proc_returncode == 0, (
                f"{self.socket_send_app} returned error"
                + f"\nstdout:\n{self.send_proc_stdout}"
                + f"\nstderr:\n{self. send_proc_stderr}"
            )
            print(f"stdout = {self.send_proc_stdout}")
            self.num_packets_sent = self.get_num_pkts_sent_from_stdout(self.send_proc_stdout)
            self.send_proc = None
        return running



    def send_recv(self, test_duration_s, payload_len="max"):
        self.set_cap_net_raw(self.socket_send_recv_app)

        ret = subprocess.run([self.socket_send_recv_app, self.eth_intf, str(test_duration_s), payload_len, self.host_mac_addr , *(self.dut_mac_addr.split())],
                             capture_output = True,
                             text = True)
        assert ret.returncode == 0, (
            f"{self.socket_send_recv_app} returned runtime error"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )
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

        ret = subprocess.run([self.socket_recv_app, self.eth_intf, self.host_mac_addr , self.dut_mac_addr, capture_file],
                             capture_output = True,
                             text = True)
        assert ret.returncode == 0, (
            f"{self.socket_recv_app} returned runtime error"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )
        # print(f"stdout = {ret.stdout}")
        # print(f"stderr = {ret.stderr}")
        m = re.search(r"Receieved (\d+) packets on ethernet interface", ret.stdout)
        assert m, ("Sniffer doesn't report received packets"
        + f"\nstdout:\n{ret.stdout}"
        + f"\nstderr:\n{ret.stderr}")

        return int(m.group(1))

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
