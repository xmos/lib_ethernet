#include <iostream>
#include <thread>
#include <cstring>
#include <unistd.h>
#include <sstream>
#include <random>
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

int get_random_int(int min, int max) {
    static thread_local std::minstd_rand rng(std::random_device{}()); // Faster than mt19937
    std::uniform_int_distribution<int> dist(min, max);
    return dist(rng);
}

// Function to send packets
void send_packets(std::string eth_intf,
                  std::string test_duration_s_str, /*Test duration in seconds*/
                  std::string packet_length_str, /* send packet length (max, min or random)*/
                  std::vector<unsigned char> src_mac, std::vector<std::vector<unsigned char>> dest_mac) {
    int sockfd;
    unsigned char packet[PACKET_SIZE];
    unsigned num_dest_mac_addresses = dest_mac.size();
    struct sockaddr_ll socket_address;

    // Create one packet per dst mac address
    std::vector<std::vector<unsigned char>> packets(num_dest_mac_addresses, std::vector<unsigned char>(PACKET_SIZE));

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

    // ensure data is transmitted before close
    struct linger sl;
    sl.l_onoff = 1;
    sl.l_linger = 5; // Allow up to 5 seconds to empty
    setsockopt(sockfd, SOL_SOCKET, SO_LINGER, &sl, sizeof(sl));

    // 4. Construct the Ethernet frame
    unsigned short ethertype = htons(ETHER_TYPE); // EtherType
    for(int i=0; i<num_dest_mac_addresses; i++)
    {
        unsigned char *pkt_ptr = packets[i].data();
        memcpy(pkt_ptr, dest_mac[i].data(), 6);     // Destination MAC
        memcpy(pkt_ptr + 6, src_mac.data(), 6);  // Source MAC
        memcpy(pkt_ptr + 12, &ethertype, 2); // EtherType
        memset(pkt_ptr + 14, 0xAB, 1500);   // Payload (Dummy Data)

    }

    std::stringstream ss(test_duration_s_str);
    float test_duration_s;
    ss >> test_duration_s;
    float test_duration_bits = test_duration_s * 100e6;

    unsigned int payload_len;
    unsigned int num_packets;

    if((packet_length_str == std::string("max")) || (packet_length_str == std::string("min")))
    {
        // payload_length is fixed so num_packets can be pre-computed
        if(packet_length_str == std::string("max"))
        {
            payload_len = 1500;
        }
        else if(packet_length_str == std::string("min"))
        {
            payload_len = 46;
        }
        unsigned packet_duration_bits = (14 + payload_len + 4)*8 + 64 + 96; // Assume Min IFG
        num_packets = (unsigned int)(test_duration_bits/packet_duration_bits);

        printf("Socket: Sending %u packets to ethernet interface %s\n", num_packets, eth_intf.c_str());

        // Send packets in a loop
        for(unsigned i=0; i<num_packets; i++)
        {
            for(int dst=0; dst<num_dest_mac_addresses; dst++)
            {
                unsigned char *pkt_ptr = packets[dst].data();
                pkt_ptr[14] = (i >> 24) & 0xff;
                pkt_ptr[15] = (i >> 16) & 0xff;
                pkt_ptr[16] = (i >> 8) & 0xff;
                pkt_ptr[17] = (i >> 0) & 0xff;
                // 5. Send the packet
                if (sendto(sockfd, pkt_ptr, (payload_len+14), 0, (struct sockaddr*)&socket_address, sizeof(socket_address)) == -1) {
                    perror("sendto");
                    close(sockfd);
                    exit(1);
                }
            }
        }
    }
    else
    {
        uint64_t test_duration_bits_i = (uint64_t)test_duration_bits;
        uint64_t total_bits_sent = 0;
        num_packets = 0;
        while(total_bits_sent < test_duration_bits_i)
        {
            int payload_len = get_random_int(46, 1500); // random number between min and max payload length

            for(int dst=0; dst<num_dest_mac_addresses; dst++)
            {
                unsigned char *pkt_ptr = packets[dst].data();
                pkt_ptr[14] = (num_packets >> 24) & 0xff;
                pkt_ptr[15] = (num_packets >> 16) & 0xff;
                pkt_ptr[16] = (num_packets >> 8) & 0xff;
                pkt_ptr[17] = (num_packets >> 0) & 0xff;
                // 5. Send the packet
                if (sendto(sockfd, pkt_ptr, (payload_len+14), 0, (struct sockaddr*)&socket_address, sizeof(socket_address)) == -1) {
                    perror("sendto");
                    close(sockfd);
                    exit(1);
                }
            }
            total_bits_sent += ((14 + payload_len + 4)*8 + 64 + 96);
            num_packets += 1;
        }
    }
    printf("Socket: Sent %u packets to ethernet interface %s\n", num_packets, eth_intf.c_str());
    close(sockfd);
}
