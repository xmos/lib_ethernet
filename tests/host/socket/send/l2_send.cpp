#include <iostream>
#include <thread>
#include <cstring>
#include <vector>
#include <sstream>
#include <unistd.h>
#include <sys/socket.h>
#include <linux/if_packet.h>
#include <net/if.h>
#include <netinet/ether.h>
#include <arpa/inet.h>
#include <sys/ioctl.h>
#include "shared.h"

int main(int argc, char *argv[]) {
	if(argc < 5)
	{
		std::cerr << "Usage: " << argv[0] << " <eth interface> <num packets to send> <host mac address> <dut mac address 1> <dut mac address 2>...<dut mac address n>\n";
		exit(1);
	}
    std::string host_mac = std::string(argv[3]);
    std::vector<std::string> dut_macs;
    dut_macs.push_back(std::string(argv[4]));
    int remaining = argc - 5;
    for(int i=0; i<remaining; i++)
    {
        dut_macs.push_back(std::string(argv[5+i]));
    }

    std::vector<unsigned char> host_mac_bytes = parse_mac_address(host_mac);
    std::vector<std::vector<unsigned char>> dut_mac_bytes;

    for(std::string dut_mac : dut_macs)
    {
        dut_mac_bytes.push_back(parse_mac_address(dut_mac));
    }

    // Start sender and receiver threads
    std::thread sender(send_packets, std::string(argv[1]), std::string(argv[2]), host_mac_bytes, dut_mac_bytes);

    // Join threads
    sender.join();

    return 0;
}

