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

extern void send_packets(std::string eth_intf, std::string num_packets_str);

int main(int argc, char *argv[]) {
	if(argc != 3)
	{
		std::cerr << "Usage: " << argv[0] << " <eth interface> <num packets to send>\n";
		exit(1);
	}

    // Start sender and receiver threads
    std::thread sender(send_packets, std::string(argv[1]), std::string(argv[2]));

    // Join threads
    sender.join();

    return 0;
}

