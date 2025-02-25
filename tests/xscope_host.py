# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
from enum import Enum, auto
import sys
import platform
from pathlib import Path
from xscope_endpoint import Endpoint, QueueConsumer

class XscopeControl():
    """
    Class for implementing functions for sending control commands to the device over xscope.
    When using this class in a standalone manner, do the following:
    In one terminal, run the dut app using xrun --xscope-port. For example:
    xrun --xscope-port localhost:12340 <xe file>
    Then in another terminal, from the tests/ directory, open a python shell and run

    from xscope_host import XscopeControl
    xscope_host = XscopeControl("localhost", "12340", verbose=True)

    Follow this with whatever commands you wish to send to the device. For example,

    xscope_host.xscope_controller_cmd_connect()
    xscope_host.xscope_controller_cmd_set_host_macaddr("a4:ae:12:77:86:97")
    xscope_host.xscope_controller_cmd_set_dut_macaddr(0, "01:02:03:04:05:06")
    xscope_host.xscope_controller_cmd_set_dut_tx_packets(0, 10000, 345)
    xscope_host.xscope_controller_cmd_shutdown()

    """
    class XscopeCommands(Enum):
        """
        Class containing supported commands that can be sent to the device over xscope.
        Extend the list below when adding a new command. The .h file for the cmd enum included in the device test apps
        is autogenerated from the list below in the CMakeLists for the test apps.
        """
        CMD_DEVICE_SHUTDOWN = auto()
        CMD_SET_DEVICE_MACADDR = auto()
        CMD_SET_HOST_MACADDR = auto()
        CMD_HOST_SET_DUT_TX_PACKETS = auto()
        CMD_SET_DUT_RECEIVE = auto()
        CMD_DEVICE_CONNECT = auto()
        CMD_EXIT_DEVICE_MAC = auto()
        CMD_SET_DUT_TX_SWEEP = auto()

        """
        Method for generating a .h file containing the enum defined above
        """
        @classmethod
        def write_to_h_file(cls, filename):
            filename = Path(filename)
            dir_path = filename.parent
            dir_path.mkdir(parents=True, exist_ok=True)

            with open(filename, "w") as fp:
                name = filename.name
                name = name.replace(".", "_")
                fp.write(f"#ifndef __{name}__\n")
                fp.write(f"#define __{name}__\n\n")
                fp.write("typedef enum {\n")
                for member in cls:
                    fp.write(f"\t{member.name} = {member.value},\n")
                fp.write("}xscope_cmds_t;\n\n")
                fp.write("#endif\n")

    def __init__(self, host, port, timeout=30, verbose=False):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.verbose = verbose
        self._ep = None

    def xscope_controller_do_command(self, cmds, connect=True):
        """
        Runs the xscope host app to connect to the DUT and execute a command over xscope port

        Parameters:
        xscope_controller: xscope host application binary
        cmds (list): byte list containing the command + arguments for the command that needs to be executed
        timeout: timeout in seconds for when not able to communicate with the device

        Returns:
        stdout and stderr from running the host application
        """
        if connect:
            ep = Endpoint()
        else:
            ep = self._ep
        probe = QueueConsumer(ep, "command_ack")

        if connect:
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

        if connect:
            ep.disconnect()
        if ack == None:
            print("Xscope host received no response from device")
            print(f"device stdout: {device_stdout}")
            assert False
        return device_stdout


    def xscope_controller_cmd_connect(self):
        """
        Run command to ensure that the xcore device is setup and ready to communicate via ethernet

        Returns:
        stdout and stderr from running the host application
        """
        return self.xscope_controller_do_command([XscopeControl.XscopeCommands['CMD_DEVICE_CONNECT'].value])


    def xscope_controller_cmd_shutdown(self):
        """
        Run command to shutdown the xcore application threads and exit gracefully

        Returns:
        stdout and stderr from running the host application
        """
        return self.xscope_controller_do_command([XscopeControl.XscopeCommands['CMD_DEVICE_SHUTDOWN'].value])

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
        cmd_plus_args = [XscopeControl.XscopeCommands['CMD_SET_DEVICE_MACADDR'].value, client_index]
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
        cmd_plus_args = [XscopeControl.XscopeCommands['CMD_SET_HOST_MACADDR'].value]
        cmd_plus_args.extend(mac_addr_bytes)
        return self.xscope_controller_do_command(cmd_plus_args)

    def xscope_controller_cmd_set_dut_tx_packets(self, client_index, arg1, arg2, connect=True):
        """
        Run command to inform the TX clients on the DUT the number of packets and length of each packet that it needs to transmit

        Parameters:
        arg1: number of packets to send for LP thread. qav bw in bps for HP thread
        arg2: packet payload length in bytes

        Returns:
        stdout and stderr from running the host application
        """
        cmd_plus_args = [XscopeControl.XscopeCommands['CMD_HOST_SET_DUT_TX_PACKETS'].value]
        for a in [client_index, arg1, arg2]: # client_index, arg1 and arg2 are int32
            bytes_to_append = [(a >> (8 * i)) & 0xFF for i in range(4)]
            cmd_plus_args.extend(bytes_to_append)
        return self.xscope_controller_do_command(cmd_plus_args, connect=connect)


    def xscope_controller_cmd_set_dut_receive(self, client_index, recv_flag):
        """
        Run command to a given RX client on the DUT to start or stop receiving packets.

        Parameters:
        client_index: RX client index on the DUT
        recv_flag: Flag indicating whether to receive (1) or not receive (0) the packet

        Returns:
        stdout and stderr from running the host application
        """
        cmd_plus_args = [XscopeControl.XscopeCommands['CMD_SET_DUT_RECEIVE'].value, client_index, recv_flag]
        return self.xscope_controller_do_command(cmd_plus_args)

    def xscope_controller_cmd_restart_dut_mac(self):
        """
        Run command to restart the DUT Mac.

        Returns:
        stdout and stderr from running the host application
        """
        return self.xscope_controller_do_command([XscopeControl.XscopeCommands['CMD_EXIT_DEVICE_MAC'].value])

    def xscope_controller_cmd_set_dut_tx_sweep(self, client_index):
        """
        Run command to get a client on the DUT to sweep through all frame sizes while transmitting.
        Parameters:
        client_index: index of the client.

        Returns:
        stdout and stderr from running the host application
        """
        cmd_plus_args = [XscopeControl.XscopeCommands['CMD_SET_DUT_TX_SWEEP'].value, client_index]
        return self.xscope_controller_do_command(cmd_plus_args)

    def xscope_controller_start_timestamp_recorder(self):
        ep = Endpoint()
        probe = QueueConsumer(ep, "tx_start_timestamp")

        if ep.connect(hostname=self.host, port=self.port):
            print("Xscope Host app failed to connect")
            assert False

        self._ep = ep
        self._probe = probe


    def xscope_controller_stop_timestamp_recorder(self):
        print(f"{self._probe.queue.qsize()} elements in the queue")
        probe_output = []
        for i in range(self._probe.queue.qsize()):
            probe_output.extend(self._probe.next())
        device_stdout = self._ep._captured_output.getvalue() # stdout from the device
        print("stdout from the device:")
        print(device_stdout)
        self._ep.disconnect()
        return probe_output



"""
Do not change the main function since it's called from CMakeLists.txt to autogenerate the xscope commands enum .h file
"""
if __name__ == "__main__":
    print("Generate xscope cmds enum .h file")
    assert len(sys.argv) == 2, ("Error: filename not provided" +
                    "\nUsage: python generate_xscope_cmds_enum_h_file.py <.h file name, eg. enum.h>\n")

    XscopeControl.XscopeCommands.write_to_h_file(sys.argv[1])


