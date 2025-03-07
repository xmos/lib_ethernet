// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef SHARED_H
#define SHARED_H

#include <string>
#include <vector>
#include <cstdint>
#include <future>

void send_packets(std::string eth_intf,
                  std::string test_duration_s_str, /*Test duration in seconds*/
                  std::string packet_length_str, /* send packet length (max, min or random)*/
                  std::vector<unsigned char> src_mac, std::vector<std::vector<unsigned char>> dest_mac);

void receive_packets(std::string eth_intf,
                        std::string cap_file,
                        std::vector<unsigned char> target_mac,
                        std::promise<void>& ready_signal);

std::vector<unsigned char> parse_mac_address(const std::string mac);

void test(const std::string &mac);

#endif

