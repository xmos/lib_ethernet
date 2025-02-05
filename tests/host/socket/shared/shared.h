#ifndef SHARED_H
#define SHARED_H

void send_packets(std::string eth_intf, std::string num_packets_str);
void receive_packets(std::string eth_intf, const unsigned char *target_mac);

#endif

