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

#define ETHER_TYPE 0x2222 // IPv4 EtherType
#define PACKET_SIZE 1514    // Ethernet frame size

// Function to send packets
void send_packets(std::string eth_intf, std::string num_packets_str, std::vector<unsigned char> src_mac, std::vector<unsigned char> dest_mac) {
    int sockfd;
    unsigned char packet[PACKET_SIZE];
    struct sockaddr_ll socket_address;

    // Create raw socket for sending
    sockfd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (sockfd < 0) {
        perror("Socket creation failed");
	exit(1);
    }

    // Get interface index
    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, eth_intf.c_str(), IFNAMSIZ - 1);
    if (ioctl(sockfd, SIOCGIFINDEX, &ifr) == -1) {
        perror("Getting interface index failed");
        close(sockfd);
	exit(1);
    }

    int ifindex = ifr.ifr_ifindex;

    int rcvbuf_size = 0;
    int sndbuf_size = 0;
    socklen_t optlen = sizeof(int);

    // Get the current receive buffer size
    if (getsockopt(sockfd, SOL_SOCKET, SO_RCVBUF, &rcvbuf_size, &optlen) < 0) {
        perror("getsockopt SO_RCVBUF failed");
        close(sockfd);
        exit(1);
    }

    // Get the current send buffer size
    if (getsockopt(sockfd, SOL_SOCKET, SO_SNDBUF, &sndbuf_size, &optlen) < 0) {
        perror("getsockopt SO_SNDBUF failed");
        close(sockfd);
        exit(1);
    }

    // Print current buffer sizes
    std::cout << "Current Receive Buffer Size (SO_RCVBUF): " << rcvbuf_size << " bytes\n";
    std::cout << "Current Send Buffer Size (SO_SNDBUF): " << sndbuf_size << " bytes\n";

#if 0
    int new_rcvbuf_size = 200000;
    setsockopt(sockfd, SOL_SOCKET, SO_RCVBUF, &new_rcvbuf_size, sizeof(new_rcvbuf_size));

    int new_sndbuf_size = 200000;  // 32 MB
    setsockopt(sockfd, SOL_SOCKET, SO_SNDBUF, &new_sndbuf_size, sizeof(new_sndbuf_size));
#endif

    // 3. Set up the sockaddr_ll structure
    memset(&socket_address, 0, sizeof(socket_address));
    socket_address.sll_family = AF_PACKET;
    socket_address.sll_protocol = htons(ETH_P_ALL);
    socket_address.sll_ifindex = ifindex;
    socket_address.sll_halen = ETH_ALEN;
    memcpy(socket_address.sll_addr, "\xAA\xBB\xCC\xDD\xEE\xFF", ETH_ALEN); // Destination MAC


    // 4. Construct the Ethernet frame
    unsigned short ethertype = htons(ETHER_TYPE); // EtherType

    memcpy(packet, dest_mac.data(), 6);     // Destination MAC
    memcpy(packet + 6, src_mac.data(), 6);  // Source MAC
    memcpy(packet + 12, &ethertype, 2); // EtherType
    memset(packet + 14, 0xAB, 1500);   // Payload (Dummy Data)

    unsigned int num_packets = std::stoi(num_packets_str);

	std::cout << "Sending: " << num_packets << " packets to ethernet interface " << eth_intf << std::endl;

    // Send packets in a loop
    for(unsigned i=0; i<num_packets; i++)
    {
	    packet[14] = (i >> 24) & 0xff;
	    packet[15] = (i >> 16) & 0xff;
	    packet[16] = (i >> 8) & 0xff;
	    packet[17] = (i >> 0) & 0xff;
        // 5. Send the packet
        if (sendto(sockfd, packet, PACKET_SIZE, 0, (struct sockaddr*)&socket_address, sizeof(socket_address)) == -1) {
            perror("sendto");
            close(sockfd);
            exit(1);
        }
    }
    close(sockfd);
}
