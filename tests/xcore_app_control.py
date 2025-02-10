import subprocess
import platform
from pathlib import Path
import re
from scapy.all import *
from hw_helpers import mii2scapy
from hardware_test_tools.XcoreApp import XcoreApp

pkg_dir = Path(__file__).parent

class XcoreAppControl(XcoreApp):
    def __init__(self, adapter_id, xe_name, attach=None):
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
        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, ["connect"], timeout)
        return stdout, stderr

    def xscope_controller_cmd_shutdown(self, timeout=30):
        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, ["shutdown"], timeout)
        return stdout, stderr

    def xscope_controller_cmd_set_dut_macaddr(self, client_index, mac_addr, timeout=30):
        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, ["set_dut_macaddr", str(client_index), str(mac_addr)], timeout)
        return stdout, stderr

    def xscope_controller_cmd_set_host_macaddr(self, mac_addr, timeout=30):
        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, ["set_host_macaddr", str(mac_addr)], timeout)
        return stdout, stderr

    def xscope_controller_cmd_set_dut_receive(self, client_index, recv_flag, timeout=30):
        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, ["set_dut_receive", str(client_index), str(recv_flag)], timeout)
        return stdout, stderr


class SocketHost():
    def __init__(self, eth_intf, host_mac_addr, dut_mac_addr):
        self.eth_intf = eth_intf
        self.host_mac_addr = host_mac_addr
        self.dut_mac_addr = dut_mac_addr
        self.send_proc = None

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

        #self.socket_recv_app = socket_host_dir / "build" / "socket_recv"
        #assert self.socket_recv_app.exists(), f"socket host app {self.socket_recv_app} doesn't exist"


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

    def send(self, num_packets):
        self.set_cap_net_raw(self.socket_send_app)

        ret = subprocess.run([self.socket_send_app, self.eth_intf, str(num_packets), self.host_mac_addr , *(self.dut_mac_addr.split())],
                             capture_output = True,
                             text = True)
        print(f"stdout = {ret.stdout}")
        assert ret.returncode == 0, (
            f"{self.socket_send_app} returned runtime error"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

    def send_non_blocking(self, num_packets):
        self.set_cap_net_raw(self.socket_send_app)
        self.send_proc = subprocess.Popen(
                [self.socket_send_app, self.eth_intf, str(num_packets), self.host_mac_addr , *(self.dut_mac_addr.split())],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )

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
            self.send_proc = None
        return running



    def send_recv(self, num_packets_to_send):
        self.set_cap_net_raw(self.socket_send_recv_app)

        ret = subprocess.run([self.socket_send_recv_app, self.eth_intf, str(num_packets_to_send), self.host_mac_addr , *(self.dut_mac_addr.split())],
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

        return int(m.group(1))

    def recv(self, capture_file):
        self.set_cap_net_raw(self.socket_recv_app)

        ret = subprocess.run([self.socket_recv_app, self.eth_intf, capture_file, self.host_mac_addr , self.dut_mac_addr],
                             capture_output = True,
                             text = True)
        assert ret.returncode == 0, (
            f"{self.socket_recv_app} returned runtime error"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )
        print(f"stdout = {ret.stdout}")
        print(f"stderr = {ret.stderr}")
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
