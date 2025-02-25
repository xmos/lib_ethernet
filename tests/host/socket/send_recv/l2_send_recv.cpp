// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <iostream>
#include <thread>
#include <cstring>
#include <unistd.h>
#include <sys/socket.h>
#include <linux/if_packet.h>
#include <net/if.h>
#include <netinet/ether.h>
#include <arpa/inet.h>
#include <sys/ioctl.h>
#include <atomic>
#include "shared.h"

int main(int argc, char *argv[])
{
	if(argc != 6)
	{
		std::cerr << "Usage: " << argv[0] << " <eth interface> <send_duration_s> <packet_length (max, min or random)> <host mac address> <dut mac address>\n";
		exit(1);
	}
    std::string host_mac = std::string(argv[4]);
    std::string dut_mac = std::string(argv[5]);

    std::vector<unsigned char> host_mac_bytes = parse_mac_address(host_mac);
    std::vector<std::vector<unsigned char>> dut_mac_bytes;
    dut_mac_bytes.push_back(parse_mac_address(dut_mac));

    // Start sender and receiver threads
    std::string no_capture_file = "";
    std::thread receiver(receive_packets, std::string(argv[1]), no_capture_file, dut_mac_bytes[0]);

    std::this_thread::sleep_for(std::chrono::seconds(2)); // Give time for receiver thread to start receiving before starting sender

    std::thread sender(send_packets, std::string(argv[1]), std::string(argv[2]), std::string(argv[3]), host_mac_bytes, dut_mac_bytes);

    // Join threads
    sender.join();
    receiver.join();

    return 0;
}

