# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

"""
This file contains various helper functions for running HW tests
"""

import subprocess
import sys
from pathlib import Path
import socket
import time
import json
from scapy.all import rdpcap, Ether, Raw, wrpcap, PcapWriter
from mii_packet import MiiPacket
import re


"""
This class contains helpers for running the Intona 7060-A Ethernet Debugger
"""
class hw_eth_debugger:
    # No need to pass binary if on the path. Device used to specify debugger if more than one
    def __init__(self, nose_bin_path=None, device=None):
        # Get the "nose" binary that drives the debugger
        if nose_bin_path is None:
            result = subprocess.run("which nose".split(), capture_output=True, text=True)
            if result.returncode == 0:
                self.nose_bin_path = Path(result.stdout.strip("\n"))
            else:
                self.nose_bin_path = self.build_binary()
        else:
            if not Path(nose_bin_path).isfile():
                raise RuntimeError(f'Nose not found on supplied path: {nose_bin_path}')

        # Setup socket for comms with debugger
        device = "" if device is None else device
        socket_path = f"/tmp/nose_socket{device}"
        device_str = "" if device == "" else f"--device {device}"

        # Startup debugger process
        # first kill any unterminated
        subprocess.run("pkill -f nose", shell=True)
        cmd = f"{str(self.nose_bin_path)} {device_str} --ipc-server {socket_path}"
        self.nose_proc = subprocess.Popen(cmd.split(), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
        # ensure is running
        while self.nose_proc.poll() is not None:
            time.sleep(0.01)
        # print(f"Nose proc running, {self.nose_proc}, cmd={cmd}")
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.timeout_s = 2 # normal timeout for command response
        self.sock.settimeout(self.timeout_s)
        print("Connecting to debugger..", end="")
        while True:
            try:
                self.sock.connect(socket_path)
                print("Connected!")
                break
            except (socket.error, ConnectionRefusedError):
                print(".", end="")
                time.sleep(.01)

        self.last_cmd = None

        self.capture_file = None # For packet capture
        self.disrupting = False # For disrupting packets

        # Will be a number in Mbit
        # This state is asynchronously reported by the debugger and so we pick these messages up
        # whenever they come during normal command responses or specifically with a blocking command
        self.link_state_a = 0
        self.link_state_b = 0
        # Cycle through device closed then open, which will force printing of PHY state
        self._send_cmd(f"device_close")
        self._get_response()
        self._send_cmd(f"device_open")
        self._get_response()

        # Ensure everything is reset from previous sessions
        self._send_cmd("reset_device_settings")
        self._get_response()

    # Destructor
    def __del__(self):
        self._send_cmd("exit")
        if self.nose_proc.poll() is None: 
            self.nose_proc.terminate()
        self.sock.close()
        print("hw_eth_debugger exited")

    # This is tested as working on Linux and Mac
    def build_binary(self):
        version_tag = "v1.6" # latest as of feb 2025. Note command protocol may change so pinning.
        # See https://github.com/intona/ethernet-debugger/tags
        repo_root = (Path(__file__).parent / "../..").resolve()
        repo_name = "ethernet-debugger"
        repo_dir = repo_root / repo_name
        binary = repo_dir / "build/nose"

        # Check to see if we have the app repo source
        if not repo_dir.is_dir():
            cmd = f"git clone --recursive --branch {version_tag} git@github.com:intona/{repo_name}.git {repo_dir}"
            result = subprocess.run(cmd.split(), check=True, text=True)
            if result.returncode != 0:
                raise(result.stderr)
        else:
            print(f"Repo {repo_dir} exists already, using that")

        if not binary.is_file():
            cmd = "meson setup build"
            result = subprocess.run(cmd.split(), check=True, text=True, cwd=repo_dir)
            if result.returncode != 0:
                raise(result.stderr + "Need to install meson for the build stage")
            cmd = "ninja -C build"
            result = subprocess.run(cmd.split(), check=True, text=True, cwd=repo_dir)
            if result.returncode != 0:
                raise(result.stderr + "Need to install ninja for the build stage")

        return binary

    def _send_cmd(self, cmd):
        self.last_cmd = cmd
        self.sock.sendall((cmd + "\n").encode('utf-8'))
        # print(f"SENT: {cmd}")

    def _get_response(self, timeout_s=None):
        # Use new timeout temporarily if needed
        if timeout_s:
            self.sock.settimeout(timeout_s)
        try:
            response = self.sock.recv(4096)
        except TimeoutError:
            return False, f"ERROR: Timeout on command response: {self.last_cmd}"
        finally:
            # restore normal timeout
            if timeout_s:
                self.sock.settimeout(self.timeout_s)

        response = response.decode("utf-8").split("\n")
        # print("RESP:", response)
        r_dict = [json.loads(json_str) for json_str in response if json_str]
        msg = []
        msg_for_human = ""
        for resp in r_dict:
            if "msg" in resp:
                new_msg_line = f'{resp["msg"]}'
                msg_for_human += new_msg_line
                # print("***", new_msg_line)
                if "Error" in new_msg_line:
                    print(new_msg_line, file=sys.stderr)
                # always check for phy status reports which are asynch
                m = re.search(r"PHY\s(\w):\slink\s(\w+)\s(.+)MBit.*", new_msg_line)
                if m:
                    phy, link, speed = m.groups()[0:3]
                    if phy == "A":
                        self.link_state_a = int(speed)
                    else:
                        self.link_state_b = int(speed)

        return True, msg_for_human


    def get_link_status(self):
        # Just quickly poll the output to get latest info in case of PHY state change and return stored state
        # This is updated on every command response anyway
        self._get_response(timeout_s=0.01)

        return self.link_state_a, self.link_state_b

    def wait_for_links_up(self, speed_mbps=100, timeout_s=5):
        print(f"Waiting up to {timeout_s}s for both links to be up at {speed_mbps}Mbps")
        time_left = timeout_s
        time_true = 0 #Links sometimes start up and then go down so ensure we get up for a while
        min_time_up = 2
        while time_left > 0:
            poll_period = 0.1
            link_a, link_b = self.get_link_status()
            if link_a == speed_mbps and link_b == speed_mbps:
                time_true += poll_period
                if time_true >= min_time_up: # Links must be constantly up for this time
                    return True
            else:
                time_true = 0
            time.sleep(poll_period)
            time_left -= poll_period
        print(f"Error links not up A: {link_a} B: {link_b} after {timeout_s} seconds", file=sys.stderr)

        return False

    """ Inject arbitraty packets or play from a file
    Parameters (from Intona):
          phy             Port/PHY
                          Type: integer or string choice
                          Required parameter.
                          Special values: A (1), B (2), AB (3), none (0), - (0)
          data            hex: 0x... 0x.. words, ABCD bytes
                          Type: string
                          Default: ''
          raw             if true, do not add preamble/SFD/CRC
                          Type: bool: true/false
                          Default: 'false'
          num             number of packets (inf=continuous mode)
                          Type: integer or string choice
                          Default: '1'
                          Special values: stop (0), inf (4294967295)
          gap             minimum IPG before/after
                          Type: integer
                          Default: '12'
          append-random   append this many random bytes
                          Type: integer
                          Default: '0'
          append-zero     append this many zero bytes
                          Type: integer
                          Default: '0'
          gen-error       generate error at byte offset
                          Type: integer or string choice
                          Default: '-1'
                          Special values: disable (-1)
          file            send packet loaded from file
                          Type: string
                          Default: ''
          loop-count      repeat packet data at end of packet
                          Type: integer or string choice
                          Default: '0'
                          Special values: inf (4294967295)
          loop-offset     repeat packet data at this offset
                          Type: integer
                          Default: '0'
          nopad           do not pad short packets to mandatory packet length
                          Type: bool: true/false
    """

    """
    Inject a packet on port A, B or AB. Pass either data as hex string eg 0123456789abcdef or <myfile.pcapng> file
    Repeats num times.
    Packets shorter than 60 bytes will be zero padded to 60 bytes
    """
    def inject_packets(self, phy, data=None, num=1, ifg_bytes=12, filename=""):
        raw = "false" # false means add preamble and CRC
        append_rand = 0
        append_zero = 0
        gen_error = -1
        if data is None and filename == "":
            raise RuntimeError("Must pass either file or data to inject")
        if data:
            cmd = f'inject {phy} {data} {raw} {num} {ifg_bytes} {append_rand} {append_zero} {gen_error} ""'
        if filename != "":
            cmd = f'inject {phy} "" {raw} {num} {ifg_bytes} {append_rand} {append_zero} {gen_error} {filename}'

        # print(f"cmd: {cmd}")
        self._send_cmd(cmd)
        # Note inject does not normally respond with anythin so set short timeout and ignore timeout warning
        ok, msg = self._get_response(timeout_s=0.001)
        if "Timeout" in msg:
            pass #This is expected
        return True

    """ 
    This converts from MiiPacket to expected format and sends num times
    """
    def inject_packet_MiiPacket(self, phy, packet, num=1, ifg_bytes=12):
        data_bytes = packet.get_packet_bytes()
        hex_string = ''.join(format(x, '02x') for x in data_bytes)
        self.inject_packets(phy, data=hex_string, num=num, ifg_bytes=ifg_bytes)

    # Only needed if we need to interrupt a long repeating inject command
    def inject_packets_stop(self):
        self.capture_file = None
        self._send_cmd(f"inject_stop")
        # Note inject_stop does not normally respond with anythin so set short timeout and ignore timeout warning
        ok, msg = self._get_response(timeout_s=0.001)
        
        return True

    def mdio_read(self, phy_num, addr):
        self._send_cmd(f"mdio_read {phy_num} {addr}")
        ok, msg = self._get_response()
        if ok and 'value' in msg:
            return int(msg.split('=0x')[1].strip(), 16)
        return False

    def mdio_write(self, phy_num, addr, value):
        self._send_cmd(f"mdio_write {phy_num} {addr} {value}")
        ok, msg = self._get_response()
        if ok and 'success' in msg:
            return True
        return False

    # Start capturing packets to file
    def capture_start(self, filename="packets.pcapng"):
        if self.capture_file is not None:
            raise RuntimeError("Trying to start capture when already started")
        self.capture_file = filename
        self._send_cmd(f"capture_start {filename}")
        ok, msg = self._get_response()
        if ok and 'succeeded' in msg:
            return True
        return False

    # Stops capture and returns the packets if successful, otherwise the error message
    def capture_stop(self):
        if self.capture_file is None:
            raise RuntimeError("Trying to stop capture when it hasn't been started")
        self._send_cmd(f"capture_stop")
        ok, msg = self._get_response()
        if ok and 'stopped' in msg:
            packets = rdpcap(self.capture_file)
            self.capture_file = None
            return packets
        else:
            self.capture_file = None
            print(msg, file=sys.stderr)
            return msg

    """Trash packets that are passing through the debugger
    phy             Port/PHY
                    Type: integer or string choice
                    Required parameter.
                    Special values: A (1), B (2), AB (3), none (0), - (0)
    mode            what to do with packets
                    Type: string choice
                    Default: 'drop'
                    Special values: drop, corrupt, err
    num             number of packets
                    Type: integer or string choice
                    Default: '1'
                    Special values: stop (0), inf (4294967295)
    skip            let N packets pass every time
                    Type: integer
                    Default: '0'
    offset          corrupt byte offset (0=preamble)
                    Type: integer
                    Default: '20'
    """
    def disrupt_packets(self, phy_num=3, mode="drop", num=1, skip=0, byte_offset=20):
        if self.disrupting:
            raise RuntimeError("Trying to start disruption of packets when already started")
        cmd = f"disrupt {phy_num} {mode} {num} {skip} {byte_offset}"
        self._send_cmd(cmd)
        success, message = self._get_response()
        self.disrupting = True
        return success, message

    def disrupt_stop(self):
        if not self.disrupting:
            raise RuntimeError("Trying to stop packet disruption when it hasn't been started")
        cmd = f"disrupt_stop"
        self._send_cmd(cmd)
        success, message = self._get_response()
        self.disrupting = False
        return success, message

    def set_speed(self, speed_mbps):
        self._send_cmd(f"speed {speed_mbps}") # You can also pass 'same' and will pick the lowest of the two
        ok, msg = self._get_response()
        if ok and 'setting speed to' in msg:
            return True
        return False

    def get_info(self):
        self._send_cmd(f"hw_info")
        ok, msg = self._get_response()
        if ok:
            info = {}
            port = "A" # state for parsing output (two ports)
            for line in msg.split('\n'):
                # print("****", line)
                if "Port B:" in line: port = "B"
                if 'Forced speed:' in line: info['speed'] = line.split(': ')[1].split(' ')[0]
                if 'Host tool version' in line: info['host_ver'] = line.split(': ')[1]
                if 'Firmware version' in line: info['fw_ver'] = line.split(': ')[1]
                if 'Packets (mod 2^32)' in line: info[f'packets_{port}'] = int(line.split('): ')[1])
                if 'Packets with CRC error' in line: info[f'crc_errors_{port}'] = int(line.split('): ')[1])
                if 'Symbol error bytes' in line: info[f'sym_error_bytes_{port}'] = int(line.split('): ')[1])
                if 'Injector inserted packets' in line: info[f'injector_inserted_packets_{port}'] = int(line.split('): ')[1])
                if 'Injector-dropped packets' in line: info[f'injector_dropped_packets_{port}'] = int(line.split('): ')[1])
                if 'Disruptor packets fried' in line: info[f'disrupted_packets_{port}'] = int(line.split('): ')[1])

            return info
        return False

# Convert MII packets to a pcap file
# Can take a single packet or a list of packets
def mii2pcapfile(mii_packets, pcapfile="packets.pcapng"):
    def mii2pcapfile_single(mii_packet, pcap_writer):
        nibbles = mii_packet.get_nibbles()
        if len(nibbles) % 2 != 0:
            print(f"Warning: padding {len(nibbles)} nibbles to {len(nibbles)+1} due to pcap writer limitations")
            nibbles.append(0)
        byte_list = [(nibbles[i] << 4) | nibbles[i + 1] for i in range(0, len(nibbles), 2)]
        pcap_writer.write(bytes(byte_list))

    with PcapWriter(pcapfile, linktype=1) as pcap_writer: 
        if isinstance(mii_packets, list):
            frames = []
            for mii_packet in mii_packets:
                mii2pcapfile_single(mii_packet, pcap_writer)
        else:
            mii2pcapfile_single(mii_packets, pcap_writer)

# Convert MII packets to scapy ethernet packets
# Can take a single packet or a list of packets
def mii2scapy(mii_packets):
    def mii_to_scapy_single(mii_packet):
        nibbles = mii_packet.get_nibbles()
        if len(nibbles) % 2 != 0:
            print(f"Warning: padding {len(nibbles)} nibbles to {len(nibbles)+1} due to scapy limitations")
            nibbles.append(0)
        byte_list = [(nibbles[i] << 4) | nibbles[i + 1] for i in range(0, len(nibbles), 2)]
        return Raw(bytes(byte_list))

    if isinstance(mii_packets, list):
        frames = []
        for mii_packet in mii_packets:
            frames.append(mii_to_scapy_single(mii_packet))
        return frames
    else:
        return mii_to_scapy_single(mii_packets)

# Convert scapy packets to MII packets
# Can take a single packet or a list of packets
def scapy2mii(scapy_packets):
    def scapy_to_mii_single(scapy_packet):
        mii = MiiPacket(None,
                        dst_mac_addr=[int(o, 16) for o in scapy_packet.dst.split(":")],
                        src_mac_addr=[int(o, 16) for o in scapy_packet.src.split(":")],
                        ether_len_type=[scapy_packet.type & 0xff, scapy_packet.type >> 8],
                        data_bytes=list(scapy_packet[Raw].load))
        return mii

    if isinstance(scapy_packets, list):
        frames = []
        for scapy_packet in scapy_packets:
            frames.append(scapy_to_mii_single(scapy_packet))
        return frames
    else:
        return scapy_to_mii_single(scapy_packets)


def get_mac_address(interface):
    try:
        output = subprocess.check_output(f"ip link show {interface}", shell=True, text=True)
        for line in output.splitlines():
            if "link/ether" in line:
                return line.split()[1]  # Extract MAC address
    except subprocess.CalledProcessError as e:
        print(f"Error: {e}")
    return None

def calc_time_diff(start_s, start_ns, end_s, end_ns):
    """
    Returns: time difference in nanoseconds
    """
    diff_s = end_s - start_s
    diff_ns = end_ns - start_ns
    if(diff_ns < 0):
        diff_s -= 1
        diff_ns += 1000000000

    return (diff_s*1000000000 + diff_ns)

# This is just for test
if __name__ == "__main__":
    dbg = hw_eth_debugger()

    print(dbg.get_link_status())
    print(dbg.mdio_write(1, 0x1, 0x7400))
    print(dbg.mdio_read(1, 0x1))
    print(dbg.capture_start())
    packets = dbg.capture_stop() 
    print(packets, packets.summary(), dir(packets))
    print(dbg.set_speed(100))
    print(dbg.get_info())
    print(dbg.wait_for_links_up())
    print(dbg.get_link_status())

    print(dbg.inject_packets("AB", data="4ce17347ccbe01020304050622ea", num=10))
    time.sleep(1)
    print(dbg.inject_packets("AB", filename="packets.pcapng", num=10000))
    print(dbg.inject_packets_stop())

    for i in range(3):
        print("linky", dbg.get_link_status())
        time.sleep(1)


    import random
    length=150
    packet = MiiPacket(rand = random.Random(),
                dst_mac_addr=[0x00, 0x01, 0x02, 0x03, 0x04, 0x05],
                src_mac_addr=[0xdc, 0xa6, 0x32, 0xca, 0xe0, 0x20],
                ether_len_type=[0x22,  0x22],
                num_data_bytes=length,
                create_data_args=['step', (1, length)])

    print(dbg.inject_packet_MiiPacket("AB", packet, num=3))

    sys.exit(0)

    packets = [packet, packet]
    print(packet.dump())
    sp = mii2scapy(packet)
    packet2 = scapy2mii(sp)
    print(packet2.dump())
    print(packet == packet2)
