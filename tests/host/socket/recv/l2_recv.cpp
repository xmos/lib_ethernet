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
	if(argc > 5 || argc < 4)
	{
		std::cerr << "Usage: " << argv[0] << " <eth interface> <host mac address> <dut mac address> [capture_file]\n";
		exit(1);
	}
    std::string eth_if = std::string(argv[1]);
    std::string host_mac = std::string(argv[2]);
    std::string dut_mac = std::string(argv[3]);
    std::string cap_file = "";
    if(argc == 5){
         cap_file = std::string(argv[4]);
    }

    std::vector<unsigned char> host_mac_bytes = parse_mac_address(host_mac);
    std::vector<unsigned char> dut_mac_bytes = parse_mac_address(dut_mac);

    // Start sender and receiver threads
    std::thread receiver(receive_packets, eth_if, cap_file, dut_mac_bytes);

    std::this_thread::sleep_for(std::chrono::seconds(2)); // Give time for receiver thread to start receiving

    // Join threads
    receiver.join();

    return 0;
}

