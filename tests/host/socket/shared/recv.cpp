#include <iostream>
#include <fstream>
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
#include <chrono>
#include <shared.h>


#define BUFFER_SIZE 65536
unsigned recvd_packets = 0;

void receive_packets(std::string eth_intf, std::string cap_file, std::vector<unsigned char> target_mac)
{
    int sockfd;
    unsigned char buffer[BUFFER_SIZE];

    // Create raw socket for receiving
    sockfd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (sockfd < 0) {
        perror("Socket creation failed");
	exit(1);
    }

    // Bind to interface
    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, eth_intf.c_str(), IFNAMSIZ - 1);
    if (ioctl(sockfd, SIOCGIFINDEX, &ifr) == -1) {
        perror("Getting interface index failed");
        close(sockfd);
	exit(1);
    }

    struct sockaddr_ll sll = {};
    sll.sll_family   = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex  = ifr.ifr_ifindex;

    if (bind(sockfd, (struct sockaddr*)&sll, sizeof(sll)) == -1) {
        perror("Binding socket failed");
        close(sockfd);
	exit(1);
    }

    struct timeval timeout;
    timeout.tv_sec = 5;
    timeout.tv_usec = 0;
    setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    // Open cap file if specified
    std::ofstream file;
    bool capture_to_file = false;

    if(!cap_file.empty()){
        capture_to_file = true;
        file.open(cap_file, std::ios::binary);

        if (!file.is_open()) { // Check if file opened successfully
            std::cerr << "Error: Could not open file for writing! - " << cap_file << std::endl;
            return;
        }
        std::cout << "Opened file for writing! - " << cap_file << std::endl;
    }

    std::cout << "[Receiver] Listening for packets on " << eth_intf << "...\n";
    auto datum = std::chrono::high_resolution_clock::now(); // get time

    // Receive packets in a loop
    while (true) {
        int bytes_received = recvfrom(sockfd, buffer, BUFFER_SIZE, 0, nullptr, nullptr);
        if (bytes_received < 0) {
	    if (errno == EAGAIN || errno == EWOULDBLOCK) {
                std::cout << "recvfrom timed out!!\n";
                break;
            }
            std::cout << "recvfrom failed. errno " << errno << std::endl;
            break;
        }

        // Extract Ethernet header
        struct ethhdr *eth = (struct ethhdr *)buffer;

        if(memcmp(eth->h_source, target_mac.data(), 6) == 0)
        {
            //std::cout << "[Receiver] Received " << bytes_received << " bytes\n";
            //std::cout << "   Src MAC: ";
            //for (int i = 0; i < 6; i++) std::cout << std::hex << (int)eth->h_source[i] << (i < 5 ? ":" : "\n");
            //std::cout << "   Dst MAC: ";
            //for (int i = 0; i < 6; i++) std::cout << std::hex << (int)eth->h_dest[i] << (i < 5 ? ":" : "\n");
            recvd_packets += 1;
        }

        if(capture_to_file){
            size_t packet_save_len = 6 + 6 + 2 + 4; // dst, src, etype, seq_id, len
            memcpy(&buffer[packet_save_len], &bytes_received, sizeof(bytes_received));
            packet_save_len += sizeof(bytes_received); // Add packet length to saved buffer.
            file.write(reinterpret_cast<const char*>(buffer), packet_save_len);
            if (!file) {
                std::cerr << "Error: Writing to file failed!" << std::endl;
                // return;
            }
        }


    }
    printf("Receieved %u packets on ethernet interface %s\n", recvd_packets, eth_intf.c_str());
    if(capture_to_file){
        file.close();
    }
    close(sockfd);
}
