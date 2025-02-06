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
	if(argc != 5)
	{
		std::cerr << "Usage: " << argv[0] << " <eth interface> <num packets to send> <host mac address> <dut mac address>\n";
		exit(1);
	}
    std::string host_mac = std::string(argv[3]);
    std::string dut_mac = std::string(argv[4]);

    std::vector<unsigned char> host_mac_bytes = parse_mac_address(host_mac);
    std::vector<unsigned char> dut_mac_bytes = parse_mac_address(dut_mac);

    // Start sender and receiver threads
    std::thread receiver(receive_packets, std::string(argv[1]), dut_mac_bytes);

    std::this_thread::sleep_for(std::chrono::seconds(2)); // Give time for receiver thread to start receiving before starting sender

    std::thread sender(send_packets, std::string(argv[1]), std::string(argv[2]), host_mac_bytes, dut_mac_bytes);

    // Join threads
    sender.join();
    receiver.join();

    return 0;
}

