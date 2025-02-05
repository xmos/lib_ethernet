# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

"""
This file contains various helper functions for running HW tests
"""

import subprocess
from pathlib import Path
import socket
import time
import json
from scapy.all import rdpcap, Ether, Raw, wrpcap
from mii_packet import MiiPacket


"""
This class contains helpers for running the Intona 7060-A Ethernet Debugger
"""
class hw_eth_debugger:
    # No need to pass binary if on the path. Device used to specify debugger if more than one
    def __init__(self, nose_bin_path=None, device=None):
        # Find the "nose" binary that drives the debugger 
        if nose_bin_path is None:
            result = subprocess.run("which nose".split(), capture_output=True, text=True)
            if result.returncode == 0:
                self.nose_bin_path = Path(result.stdout.strip("\n"))
            else:
                raise RuntimeError('Nose not found on system path')
        else:
            if not Path(nose_bin_path).isfile():
                raise RuntimeError(f'Nose not found on supplied path: {nose_bin_path}')

        # Setup socket for comms with debugger
        device = "" if device is None else device
        socket_path = f"/tmp/nose_socket{device}"
        device_str = "" if device == "" else f"--device {device}"

        # Startup debugger process
        cmd = f"{str(self.nose_bin_path)} {device_str} --ipc-server {socket_path}"
        self.nose_proc = subprocess.Popen(cmd.split(), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
        # self.nose_proc = subprocess.Popen(cmd.split())
        print(f"Nose proc running, {self.nose_proc}, cmd={cmd}")
        # Wait until it is up and running before issuing commands
        time.sleep(1)

        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(socket_path)

        self.capture_file = None # For packet capture
        self.disrupting = False # For disrupting packets  

    # Destructor     
    def __del__(self):
        self._send_cmd("exit")
        self.nose_proc.terminate()
        self.sock.close()
        print("hw_eth_debugger exited")

    def _send_cmd(self, cmd):
        self.sock.sendall((cmd + "\n").encode('utf-8'))
        print(f"SENT: {cmd}")

    def _get_response(self):
        response = self.sock.recv(1024)
        response = response.decode("utf-8").split("\n")
        print("RESP:", response)
        r_dict = [json.loads(json_str) for json_str in response if json_str]

        success = False
        msg = []
        msg_for_human = ""
        for resp in r_dict:
            if "success" in resp:
                success = resp["success"]
            if "msg" in resp:
                msg_for_human += f'{resp["msg"]}'

        return success, msg_for_human

    # This may be deletd in the future. Plain text seems to be easier
    def _send_cmd_json(self, cmd):
        print("pre send")
        elements = cmd.split()
        json_cmd = dict()
        json_cmd["command"] = elements[0]
        params = elements[1:]
        # if len(params) % 2 != 0:
        #     raise RuntimeError(f'Params should be in pairs: {params}')
    
        if len(params):
            # for name, val in zip(params[::2], params[1::2]):
                # json_cmd[name] = val
            for param in params:
                pass

        print(json_cmd)
        self.sock.sendall((json.dumps(json_cmd) + "\n").encode('utf-8'))
        print(f"{cmd} sent")

    def get_version(self):
        self._send_cmd("hw_info")
        return self._get_response()

    """ Inject arbitraty packets or play from a file
    Parameters:
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
    def inject_packets(self, phy_num, data, num=1, ifg_bytes=12, file=""):
        raw = "false"
        append = 0
        gen_error = -1
        loop_repeat_count = 1
        cmd = f"inject {phy_num} {data} {raw} {num} {ifg_bytes} {append} {append} {gen_error} {file} {loop_repeat_count}"
        self._send_cmd(cmd)
        return self._get_response()
    
    def inject_packets_stop(self):
        cmd = f"inject_stop"
        self.capture_file = None
        self._send_cmd(cmd)
        return self._get_response()

    def mdio_read(self, phy_num, addr):
        cmd = f"mdio_read {phy_num} {addr}"
        self._send_cmd(cmd)
        return self._get_response()

    def mdio_write(self, phy_num, addr, value):
        cmd = f"mdio_read {phy_num} {addr} {value}"
        self._send_cmd(cmd)
        return self._get_response()

    # Start capturing packets to file
    def capture_start(self, filename="packets.pcapng"):
        if self.capture_file is not None:
            raise RuntimeError("Trying to start capture when already started")
        self.capture_file = filename
        cmd = f"capture_start {filename}"
        self._send_cmd(cmd)
        return self._get_response()

    # Stops capture and returns the packets if successful, otherwise the error message
    def capture_stop(self):
        if self.capture_file is None:
            raise RuntimeError("Trying to stop capture when it hasn't been started")
        cmd = f"capture_stop"
        self._send_cmd(cmd)
        success, message = self._get_response()
        if success:
            packets = rdpcap(self.capture_file)
            self.capture_file = None
            return success, packets
        else:
            self.capture_file = None
            return success, message

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
        

# Convert MII packets to scapy ethernet packets
# Can take a single packet or a list of packets
def mii2scapy(mii_packets):
    def mii_to_scapy_single(mii_packet):
        byte_data = bytes(mii_packet.data_bytes)
        ethertype = mii_packet.ether_len_type[0] + (mii_packet.ether_len_type[1] << 8)
        return Ether(dst=mii_packet.dst_mac_addr_str, src=mii_packet.src_mac_addr_str, type=ethertype)/Raw(load=byte_data)
    
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

# This is just for test
if __name__ == "__main__":
    # dbg = hw_eth_debugger()
    # print(dbg.get_version())
    # print(dbg.inject_packets(1, "deadbeef"))
    # print(dbg.inject_packets_stop())
    # print(dbg.mdio_read(1, 0))

    import random
    length=150
    packet = MiiPacket(rand = random.Random(),
                dst_mac_addr=[0x00, 0x01, 0x02, 0x03, 0x04, 0x05],
                src_mac_addr=[0xdc, 0xa6, 0x32, 0xca, 0xe0, 0x20],
                ether_len_type=[0x22,  0x22],
                num_data_bytes=length,
                create_data_args=['step', (1, length)])

    packets = [packet, packet]
    print(packet.dump())
    sp = mii2scapy(packet)
    packet2 = scapy2mii(sp)
    print(packet2.dump())
    print(packet == packet2)
