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
from decimal import Decimal
import statistics
from scapy.all import rdpcap, Ether, Raw, wrpcap, PcapNgWriter
from mii_packet import MiiPacket
import re
from collections import defaultdict
from pprint import pformat
import random
from types import SimpleNamespace
from mii_clock import Clock
import platform
from xcore_app_control import XcoreAppControl
from helpers import create_expect, create_if_needed
import Pyxsim as px
import inspect
from pcapng import FileScanner # I found a bug in rdpcap in scapy 2.6.1. This seems more robust: python-pcapng==2.1.1

# Constants used in the tests
packet_overhead = 8 + 4 + 12 # preamble, CRC and IFG
line_speed = 100e6


"""
This class contains helpers for running the Intona 7060-A Ethernet Debugger
"""
class hw_eth_debugger:
    # No need to pass binary if on the path. Device used to specify debugger if more than one
    def __init__(self, nose_bin_path=None, device=None, verbose=False):
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
        print("Killing old process..", end="")
        running = True
        while running:
            try:
                subprocess.check_output(["pgrep", "-x", "nose"], stderr=subprocess.DEVNULL)
                print(".", end="")
            except subprocess.CalledProcessError:
                print("Killed!")
                running = False
            time.sleep(0.01)

        time.sleep(0.1) # ensure is dead otherwise starting may come too soon
        cmd = f"{str(self.nose_bin_path)} {device_str} --ipc-server {socket_path}"
        self.nose_proc = subprocess.Popen(cmd.split(), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
        # ensure is running
        while self.nose_proc.poll() is not None:
            time.sleep(0.01)
        # print(f"Nose proc running, {self.nose_proc}, cmd={cmd}")
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.timeout_s = 2 # normal timeout for command response
        self.sock.settimeout(self.timeout_s)
        print("Connecting to debugger process..", end="")
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
        self.verbose = verbose

        # These are fixed in the test harness
        self.debugger_phy_to_dut = "A"
        self.debugger_phy_to_host = "B"

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
        time.sleep(0.1) # Ensure debugger is up. Previously we got to next cmd before it was up.

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

    def power_cycle_phy(self, phy='AB', delay_s=0):
        """
        Power cycle one or both of the debugger PHYs.
        Note, this function doesn't check if the link is back up after power cycle
        Args:
            phy (str): Which PHYs to power cycle. Optional. If not specified, default behaviour is
            to power down both PHYs.
            Allowed values: 'A' - power cycle PHY A, 'B' - power cycle PHY B, 'AB' - power cycle both PHY A and B

            delay_s (float): Optional. Delay between powering the phy down and back up.

        Returns:
            bool : True if successfully power cycled the PHYs, False otherwise
        """
        allowed_phy_args = ['A', 'B', 'AB']
        if phy not in allowed_phy_args:
            print(f"Invalid 'phy' argument provided to power_cycle_phy(). Provide one of {allowed_phy_args}")
            return False

        self._get_response(timeout_s=0.01) # Drain any existing responses. The first mdio_read() fails otherwise since the response returned is 'Starting capture thread succeeded.'
        bmcr_reg_index = 0 # basic mode control reg
        power_down_bit = 11 # Power Down bit offset in BMCR register
        control_val = self.mdio_read(phy, bmcr_reg_index)
        if not control_val:
            print(f"mdio_read({phy}, {bmcr_reg_index}) returned error")
            return False
        if self.verbose:
            print(f"MDIO read of reg {bmcr_reg_index} for phy {phy} returned {control_val:x}")

        # Power down the PHY
        control_val |= (1 << power_down_bit)
        if self.verbose:
            print(f"write control_val = {control_val:x}")
        ret = self.mdio_write(phy, bmcr_reg_index, control_val)
        if ret:
            control_val = self.mdio_read(phy, bmcr_reg_index)
            if not control_val:
                print(f"mdio_read({phy}, {bmcr_reg_index}) returned error")
                return False
            if self.verbose:
                print(f"MDIO read of reg {bmcr_reg_index} for phy {phy} returned {control_val:x}")
        else:
            print(f"mdio_write({phy}, {bmcr_reg_index}, {control_val}) returned False")
            return False

        # Wait before powering up
        if self.verbose:
            print(f"Sleeping {delay_s} s")
        time.sleep(delay_s)

        # Power up the PHY
        control_val &= (~(1 << power_down_bit))
        if self.verbose:
            print(f"write control_val = {control_val:x}")
        ret = self.mdio_write('A', bmcr_reg_index, control_val)
        if ret:
            control_val = self.mdio_read('A', bmcr_reg_index)
            if not control_val:
                print(f"mdio_read(A, {bmcr_reg_index}) returned error")
                return False
            if self.verbose:
                print(f"MDIO read of reg {bmcr_reg_index} for phy A returned {control_val:x}")
        else:
            print(f"mdio_write(A, {bmcr_reg_index}, {control_val}) returned False")
            return False



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

    """ Inject arbitraty packet or read from a file (WARNING - ONLY SUPPORTS ONE PACKET IN FILE)
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
    def inject_packet(self, phy, data=None, num=1, append_preamble_crc=True, ifg_bytes=12, filename=""):
        raw = "false" if append_preamble_crc else "true"
        append_rand = 0
        append_zero = 0
        gen_error = -1
        if data is None and filename == "":
            raise RuntimeError("Must pass either file or data string to inject")
        if data:
            cmd = f'inject {phy} {data} {raw} {num} {ifg_bytes} {append_rand} {append_zero} {gen_error} ""'
        if filename != "":
            cmd = f'inject {phy} "" {raw} {num} {ifg_bytes} {append_rand} {append_zero} {gen_error} {filename}'

        # print(f"cmd: {cmd}")
        self._send_cmd(cmd)
        # Note inject start does not normally respond with anything so set short timeout and ignore timeout warning
        ok, msg = self._get_response(timeout_s=0.001)
        if "Timeout" in msg:
            pass #This is expected
        return True

    """
    This converts from MiiPacket to expected format and sends num times
    Only works for properly formed packets
    """
    def inject_MiiPacket(self, phy, packet, num=1, ifg_bytes=12):
        nibbles = packet.get_nibbles()
        if len(nibbles) % 2 != 0:
            print(f"Warning: padding packet by {len(nibbles)} nibbles to {len(nibbles)+1} due to debugger inject limitations")
            nibbles.append(0)
        byte_list = [(nibbles[i + 1] << 4) | nibbles[i] for i in range(0, len(nibbles), 2)]
        hex_string = bytes(byte_list).hex()
        self.inject_packet(phy, data=hex_string, num=num, append_preamble_crc=False, ifg_bytes=ifg_bytes)

        return hex_string

    # Only needed if we need to interrupt a long repeating inject command.
    # Injecting only disrupts traffic whilst packets are sending.
    def inject_packet_stop(self):
        self.capture_file = None
        self._send_cmd(f"inject_stop")
        # Note inject_stop does not normally respond with anythin so set short timeout and ignore timeout warning
        ok, msg = self._get_response(timeout_s=0.001)

        return True

    def mdio_read(self, phy_num, addr):
        self._send_cmd(f"mdio_read {phy_num} {addr}")
        ok, msg = self._get_response()
        if self.verbose:
            print(f"mdio_read {phy_num} {addr} returned ok {ok}, msg {msg}")

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
        if self.verbose:
            print(f"cmd: capture_start {filename}, returned ok {ok}, msg {msg}")
        if ok and 'succeeded' in msg:
            return True
        return False

    # Stops capture and returns the scapy packets if successful, otherwise the error message
    def capture_stop(self, use_raw=False):
        if self.capture_file is None:
            raise RuntimeError("Trying to stop capture when it hasn't been started")
        ok, msg = self._get_response() # drain out any previous responses
        self._send_cmd(f"capture_stop")
        ok, msg = self._get_response()
        if ok and 'stopped' in msg:
            if use_raw:
                #### WARNING BUG IN SCAPY IN RARE CASES SO USING THIS INSTEAD ##### 
                packets = []
                with open(self.capture_file, 'rb') as fp:
                    scanner = FileScanner(fp)
                    for block in scanner:
                        raw = block._decoded
                        if "packet_data" in raw.keys():
                            packets.append(raw["packet_data"])
                #### END OF WARNING ####
            else:
                packets = rdpcap(self.capture_file)
            print(f"Total packets: {len(packets)}")
            self.capture_file = None
            return packets
        else:
            print("ERROR!!!!")
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
            print(f"Warning: padding {len(nibbles)} nibbles to {len(nibbles)+1} due to pcapng writer limitations")
            nibbles.append(0)
        byte_list = [(nibbles[i + 1] << 4) | nibbles[i] for i in range(0, len(nibbles), 2)]
        pcap_writer.write(bytes(byte_list))


    with PcapNgWriter(pcapfile) as pcap_writer:
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


# Take scapy packets from eth debgugger and report which of them are present in
# a reference miipacket list. Provides output the same as the PHY model for
# checking against expect files. Can swap src_dst for compare where packets have been looped back
def analyse_dbg_cap_vs_sent_miipackets(received_scapy_packets, sent_mii_packets, swap_src_dst=False):
    report = ""
    last_idx_found_in_sent = 0 # To avoid searching from the start each time
    for rcvd_idx, pkt in enumerate(received_scapy_packets):
        raw_data = bytes(pkt)
        preamble = raw_data[:8] # Note this capture has complete frame including preamble and CRC
        dst_mac = raw_data[8:14]
        src_mac = raw_data[14:20]
        etype = raw_data[20:22]
        payload = raw_data[22:-4]
        crc = raw_data[-4:]

        vlan_tpid = [0x81, 0x00]  # VLAN TPID identifier
        vlan_tag = None
        if list(etype) == vlan_tpid:
            vlan_tag = raw_data[20:24]
            payload = raw_data[26:-4]
            etype = raw_data[24:26]

        # print(f"Len: {len(payload)}, Source MAC: {src_mac.hex()}, Destination MAC: {dst_mac.hex()}, etype: {etype.hex()}, VLAN: {vlan_tag} CRC: {crc.hex()}, {src_mac.hex()}, Payload (Hex): {payload.hex()}")
        # print(f"Raw: {raw_data.hex()}")
        # Now turn into MII packet for comparison
        miipacket = MiiPacket(rand=random.Random(), blank=True)
        if swap_src_dst:
            miipacket.dst_mac_addr = list(src_mac)
            miipacket.src_mac_addr = list(dst_mac)
        else:
            miipacket.dst_mac_addr = list(dst_mac)
            miipacket.src_mac_addr = list(src_mac)
        miipacket.ether_len_type = list(etype)
        miipacket.data_bytes = list(payload)
        miipacket.num_data_bytes = len(miipacket.data_bytes)
        if vlan_tag:
            miipacket.vlan_prio_tag = list(vlan_tag)

        # look for the received packet now in miipacket format in the sent packet list, making sure we shrink the sent list as we move through
        # to avoid the case where two sent packets are the same in the sent sequence.
        try:
            index = sent_mii_packets[last_idx_found_in_sent:].index(miipacket) + last_idx_found_in_sent
            report += f"Received packet {index} ok\n"
            last_idx_found_in_sent = index
        except ValueError:
            pass


    report += "Test done\n"

    print(report)

    return report

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


def load_packet_file(filename):
    chunk_size = 6 + 6 + 2 + 4 + 4 + 8 + 8
    structures = []
    with open(filename, 'rb') as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break

            dst = int.from_bytes(chunk[:6], byteorder='big')
            src = int.from_bytes(chunk[6:12], byteorder='big')
            etype = int.from_bytes(chunk[12:14], byteorder='big')
            seqid = int.from_bytes(chunk[14:18], byteorder='little')
            length = int.from_bytes(chunk[18:22], byteorder='little')
            time_s = int.from_bytes(chunk[22:30], byteorder='little')
            time_ns = int.from_bytes(chunk[30:38], byteorder='little')

            structures.append([dst, src, etype, seqid, length, time_s, time_ns])

    return structures

def rdpcap_to_packet_summary(packets):
    structures = []
    for packet in packets:
        raw_payload = bytes(packet.payload)
        dst = int.from_bytes(raw_payload[:6], byteorder='big')
        src = int.from_bytes(raw_payload[6:12], byteorder='big')
        etype = int.from_bytes(raw_payload[12:14], byteorder='big')
        seqid = int.from_bytes(raw_payload[14:18], byteorder='little')
        length = len(raw_payload)
        time_s, fraction = divmod(packet.time, 1)  # provided in 'Decimal' python format
        time_s = int(time_s)
        time_ns = int(fraction * Decimal('1e9'))

        structures.append([dst, src, etype, seqid, length, time_s, time_ns])
    return structures

def log_ifg_summary(ifg_full_dict,
                    ifg_summary_file="ifg_sweep_summary.txt",
                    ifg_full_file="ifg_sweep_full.txt"
                    ):
    ifg_summary_dict = defaultdict(dict)
    all_ifgs = []
    for pl in ifg_full_dict: # Look at the IFGs one payload length at a time and summarise
        all_ifgs.extend(ifg_full_dict[pl])
        min_ifg_pl = min(ifg_full_dict[pl])
        max_ifg_pl = max(ifg_full_dict[pl])
        if len(ifg_full_dict[pl]) > 1:
            std_dev_ifg_pl = statistics.stdev(ifg_full_dict[pl])
        else:
            std_dev_ifg_pl = 0.0

        mean_ifg_pl = statistics.mean(ifg_full_dict[pl])
        ifg_summary_dict[pl] = {"min": round(min_ifg_pl, 2), "max": round(max_ifg_pl, 2), "mean": round(mean_ifg_pl, 2), "std_dev": round(std_dev_ifg_pl, 2)}

    min_ifg = min(all_ifgs)
    max_ifg = max(all_ifgs)
    std_dev_ifg = statistics.stdev(all_ifgs)
    mean_ifg = statistics.mean(all_ifgs)

    with open(ifg_summary_file, "w") as f:
        f.write("After sweeping through all valid payload lengths:\n")
        f.write(f"Overall max IFG = {round(max_ifg,2)}\n")
        f.write(f"Overall min IFG = {round(min_ifg,2)}\n")
        f.write(f"Overall mean IFG = {round(mean_ifg,2)}\n")
        f.write("\nIFG summary per payload length\n")
        f.write(pformat(ifg_summary_dict))

    with open(ifg_full_file, "w") as f:
        f.write("IFG all frames per payload length\n")
        f.write(pformat(ifg_full_dict))

def parse_packet_summary(packet_summary,
                        expected_count_lp,
                        expected_packet_len_lp,
                        dut_mac_address_lp,
                        expected_packet_len_hp = 0,
                        dut_mac_address_hp = 0,
                        expected_bandwidth_hp = 0,
                        start_seq_id_lp = 0,
                        verbose = False,
                        check_ifg = False,
                        log_ifg_per_payload_len=False):
    print("Parsing packet file")
    # get first packet time with valid source addr
    datum = 0
    for packet in packet_summary:
        if packet[1] == dut_mac_address_lp or packet[1] == dut_mac_address_hp:
            datum = int(packet[5] * 1e9 + packet[6])
            break

    errors = ""
    expected_seqid_lp = start_seq_id_lp
    expected_seqid_hp = 0
    counted_lp = 0
    counted_hp = 0
    last_valid_packet_time = 0
    last_length = 0 # We need this for checking IFG
    ifgs = []
    ifg_full_dict = defaultdict(list) # dictionary containing IFGs seen for each payload length

    for packet in packet_summary:
        dst = packet[0]
        src = packet[1]
        seqid = packet[3]
        length = packet[4]
        tv_s = packet[5]
        tv_ns = packet[6]
        packet_time = int(tv_s * 1e9 + tv_ns) - datum

        if src == dut_mac_address_lp:
            if (expected_packet_len_lp != 0) and (length != expected_packet_len_lp):
                errors += f"Incorrect LP length at seqid: {seqid}, expected: {expected_packet_len_lp} got: {length}\n"
            if seqid != expected_seqid_lp:
                errors += f"Missing LP seqid: {expected_seqid_lp}, got: {seqid}\n"
                expected_seqid_lp = seqid
            expected_seqid_lp += 1
            counted_lp += 1

        if src == dut_mac_address_hp:
            if length != expected_packet_len_hp:
                errors += f"Incorrect HP length at seqid: {seqid}, expected: {expected_packet_len_hp} got: {length}\n"
            if seqid != expected_seqid_hp:
                errors += f"Missing HP seqid: {expected_seqid_hp}, got: {seqid}\n"
                expected_seqid_hp = seqid
            expected_seqid_hp += 1
            counted_hp += 1

        if src == dut_mac_address_lp or src == dut_mac_address_hp:
            if check_ifg:
                packet_time_diff_ns = packet_time - last_valid_packet_time
                packet_time_ns = 1e9 / line_speed * 8 * (last_length + 4 + 8) #preamble and CRC only
                ifg_ns = packet_time_diff_ns - packet_time_ns
                ifgs.append(ifg_ns)
                if log_ifg_per_payload_len:
                    if(last_length == length): # log IFG seen between packets of the same length
                        ifg_full_dict[length].append(ifg_ns)
            # ensure we only count valid packets for bandwidth calc
            last_valid_packet_time = packet_time
            last_length = length

    if expected_bandwidth_hp:
        total_time_ns = last_valid_packet_time # Last packet time
        num_bits_hp = counted_hp * (expected_packet_len_hp + packet_overhead) * 8
        bits_per_second = num_bits_hp / (total_time_ns / 1e9)
        difference_pc = abs(expected_bandwidth_hp - bits_per_second) / abs(expected_bandwidth_hp) * 100
        allowed_tolerance_pc = 0.1 # How close HP bandwidth should be for test pass in %
        text = f"Calculated HP thoughput: {bits_per_second:.1f}, expected throughput: {expected_bandwidth_hp:.1f}, diff: {difference_pc:.2f}% (max: {allowed_tolerance_pc:.2f}%)"
        if difference_pc > allowed_tolerance_pc:
            errors += text
        if verbose:
            print(text)

    if check_ifg:
        if len(ifgs) > 15:
            ifgs = ifgs[1:-10] # The first is always wrong as is the datum and last few are HP dominared with gaps as LP tx shuts down first
        min_ifg = min(ifgs)
        max_ifg = max(ifgs)
        std_dev_ifg = statistics.stdev(ifgs)
        mean_ifg = statistics.mean(ifgs)
        counter_dict = {}
        for ifg in ifgs:
            counter_dict[ifg] = counter_dict.get(ifg, 0) + 1
        print(f"IFG stats min: {min_ifg:.2f} max: {max_ifg:.2f} mean: {mean_ifg:.2f} std_dev: {std_dev_ifg:.2f}")
        print(f"IFG instances: {counter_dict}")

    if (expected_count_lp > 0) and (counted_lp != expected_count_lp):
        errors += f"Did not get: {expected_count_lp} LP packets, got: {counted_lp} (dropped: {expected_count_lp-counted_lp})"

    if verbose:
        print(f"Counted {counted_lp} LP packets and {counted_hp} HP packets over {last_valid_packet_time/1e9:.2f}s")

    return errors if errors != "" else None, counted_lp, counted_hp, ifg_full_dict

def hw_4_1_x_test_init(seed):
    random.seed(seed)
    seed = random.randint(0, sys.maxsize)
    mac = "rt_hp"
    arch = "xs3"
    name = "rmii"
    phy = SimpleNamespace(get_name=lambda: name,
                          get_clock=lambda: SimpleNamespace(get_bit_time=lambda: 100000.0))
    clock = SimpleNamespace(get_rate=lambda: Clock.CLK_50MHz,
                            get_min_ifg=lambda: 960000000.0)

    caller_frame = inspect.currentframe().f_back  # Get the caller's frame
    testname = caller_frame.f_code.co_name + "_" + name # Extract the caller's function name

    return seed, testname, mac, arch, phy, clock

# Runner for eth debugger rx_test used by 4_1_x etc.
def do_hw_dbg_rx_test(request, testname, mac, arch, packets_to_send):
    testname += "_" + mac + "_" + arch
    pkg_dir = Path(__file__).parent
    send_method = "debugger"

    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id != None, "Error: Specify a valid adapter-id"

    verbose = False

    dut_mac_address_str = "00:01:02:03:04:05"
    print(f"dut_mac_address = {dut_mac_address_str}")
    dut_mac_address = [int(i, 16) for i in dut_mac_address_str.split(":")]

    if send_method == "debugger":
        assert platform.system() in ["Linux"], f"HW debugger only supported on Linux"
        dbg = hw_eth_debugger()
    else:
        assert False, f"Invalid send_method {send_method}"

    xe_name = pkg_dir / "hw_test_mii" / "bin" / "loopback" / "hw_test_mii_loopback.xe"
    with XcoreAppControl(adapter_id, xe_name, attach="xscope_app", verbose=verbose) as xcoreapp:
        print("Wait for DUT to be ready")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_connect()

        print("Set DUT Mac address")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_set_dut_macaddr(0, dut_mac_address_str)

        if send_method == "debugger":
            if dbg.wait_for_links_up():
                print("Links up")
            else:
                raise RuntimeError("Links not up")
            dbg.capture_start("packets_received.pcapng")

            print("Debugger sending packets")
            for packet_to_send in packets_to_send:
                dbg.inject_MiiPacket(dbg.debugger_phy_to_dut, packet_to_send)
            time.sleep(0.1) # Allow last packet to depart before stopping capture. 0.01s normally plenty but add margin

            received_packets = dbg.capture_stop(use_raw=True)

        print("Retrive status and shutdown DUT")
        stdout = xcoreapp.xscope_host.xscope_controller_cmd_shutdown()
        print("Terminating!!!")

    # Analyse and compare against expected
    report = analyse_dbg_cap_vs_sent_miipackets(received_packets, packets_to_send, swap_src_dst=True) # Packets are looped back so swap MAC addresses for filter
    if verbose: print(report)
    expect_folder = create_if_needed("expect_temp")
    expect_filename = f'{expect_folder}/{testname}.expect'
    create_expect(packets_to_send, expect_filename)
    tester = px.testers.ComparisonTester(open(expect_filename))

    assert tester.run(report.split("\n")[:-1]) # Need to chop off last line

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

    print(dbg.inject_packet("AB", data="4ce17347ccbe01020304050622ea", num=10))
    time.sleep(1)
    print(dbg.inject_packet("AB", filename="packets.pcapng", num=10000))
    print(dbg.inject_packet_stop())

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
