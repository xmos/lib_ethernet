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

#define ETHER_TYPE 0x2222 // IPv4 EtherType
#define PACKET_SIZE 1514    // Ethernet frame size
#define BUFFER_SIZE 65536

unsigned recvd_packets = 0;

void receive_packets(std::string eth_intf, const unsigned char *target_mac)
{
    int recv_sockfd;
    unsigned char buffer[BUFFER_SIZE];

    // Create raw socket for receiving
    recv_sockfd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (recv_sockfd < 0) {
        perror("Socket creation failed");
	exit(1);
    }

    // Bind to interface
    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, eth_intf.c_str(), IFNAMSIZ - 1);
    if (ioctl(recv_sockfd, SIOCGIFINDEX, &ifr) == -1) {
        perror("Getting interface index failed");
        close(recv_sockfd);
	exit(1);
    }

    struct sockaddr_ll sll = {};
    sll.sll_family   = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex  = ifr.ifr_ifindex;

    if (bind(recv_sockfd, (struct sockaddr*)&sll, sizeof(sll)) == -1) {
        perror("Binding socket failed");
        close(recv_sockfd);
	exit(1);
    }

    struct timeval timeout;
    timeout.tv_sec = 5;
    timeout.tv_usec = 0;
    setsockopt(recv_sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    std::cout << "[Receiver] Listening for packets on " << eth_intf << "...\n";

    // Receive packets in a loop
    while (true) {
        int bytes_received = recvfrom(recv_sockfd, buffer, BUFFER_SIZE, 0, nullptr, nullptr);
        if (bytes_received < 0) {
	    if (errno == EAGAIN || errno == EWOULDBLOCK) {
	    	std::cout << "recvfrom timed out!!\n";
                // Timeout occurred, check stop flag
                break;
            }
	    std::cout << "recvfrom failed\n";
            perror("recvfrom failed");
            break;
        }

        // Extract Ethernet header
        struct ethhdr *eth = (struct ethhdr *)buffer;
        
        if(memcmp(eth->h_source, target_mac, 6) == 0)
        {
            //std::cout << "[Receiver] Received " << bytes_received << " bytes\n";
            //std::cout << "   Src MAC: ";
            //for (int i = 0; i < 6; i++) std::cout << std::hex << (int)eth->h_source[i] << (i < 5 ? ":" : "\n");
            //std::cout << "   Dst MAC: ";
            //for (int i = 0; i < 6; i++) std::cout << std::hex << (int)eth->h_dest[i] << (i < 5 ? ":" : "\n");
            recvd_packets += 1;
        }

    }
    std::cout << "Receiver exiting. Received " << recvd_packets << " packets\n";

    close(recv_sockfd);
}


// Function to send packets
void send_packets(std::string eth_intf, std::string num_packets_str) {
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
    int new_sndbuf_size = 100000;  // 32 MB
    setsockopt(sockfd, SOL_SOCKET, SO_SNDBUF, &new_sndbuf_size, sizeof(new_sndbuf_size));
    setsockopt(sockfd, SOL_SOCKET, SO_RCVBUF, &new_sndbuf_size, sizeof(new_sndbuf_size));

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
#endif

    // 3. Set up the sockaddr_ll structure
    memset(&socket_address, 0, sizeof(socket_address));
    socket_address.sll_family = AF_PACKET;
    socket_address.sll_protocol = htons(ETH_P_ALL);
    socket_address.sll_ifindex = ifindex;
    socket_address.sll_halen = ETH_ALEN;
    memcpy(socket_address.sll_addr, "\xAA\xBB\xCC\xDD\xEE\xFF", ETH_ALEN); // Destination MAC


    // 4. Construct the Ethernet frame
    unsigned char dest_mac[6] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05}; // Destination MAC
    unsigned char src_mac[6]  = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55}; // Source MAC
    unsigned short ethertype = htons(ETHER_TYPE); // EtherType

    memcpy(packet, dest_mac, 6);     // Destination MAC
    memcpy(packet + 6, src_mac, 6);  // Source MAC
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

int main(int argc, char *argv[]) {
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

