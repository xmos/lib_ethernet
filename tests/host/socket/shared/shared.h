#ifndef SHARED_H
#define SHARED_H

#include <string>
#include <vector>
#include <cstdint>

void send_packets(std::string eth_intf, std::string num_packets_str, std::vector<unsigned char> src_mac, std::vector<std::vector<unsigned char>> dest_mac);
void receive_packets(std::string eth_intf, std::vector<unsigned char> dest_mac);

std::vector<unsigned char> parse_mac_address(const std::string mac);

void test(const std::string &mac);

#endif

