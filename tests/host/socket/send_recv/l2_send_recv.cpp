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


extern unsigned recvd_packets;

extern void receive_packets(std::string eth_intf, const unsigned char *target_mac);
extern void send_packets(std::string eth_intf, std::string num_packets_str);


int main(int argc, char *argv[])
{
	if(argc != 3)
	{
		std::cerr << "Usage: " << argv[0] << " <eth interface> <num packets to send>\n";
		exit(1);
	}
    unsigned char dut_mac_addr[6] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05};
    // Start sender and receiver threads
    std::thread receiver(receive_packets, std::string(argv[1]), dut_mac_addr);

    std::this_thread::sleep_for(std::chrono::seconds(2)); // Give time for receiver thread to start receiving before starting sender

    std::thread sender(send_packets, std::string(argv[1]), std::string(argv[2]));

    // Join threads
    sender.join();
    receiver.join();

    std::cout << "Receiver received " << recvd_packets << " packets" << std::endl;
    return 0;
}

