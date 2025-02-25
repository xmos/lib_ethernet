// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <iostream>
#include <thread>
#include <cstring>
#include <sstream>
#include <vector>
#include <unistd.h>

std::vector<unsigned char> parse_mac_address(std::string mac)
{
    std::vector<unsigned char> mac_bytes;
    // Parse a string like "a4:ae:12:77:86:97" into a vector containing the 6 mac address bytes
    std::stringstream ss(mac);
    std::string byte;

    while (std::getline(ss, byte, ':')) {  // Split by ':'
        mac_bytes.push_back(static_cast<uint8_t>(std::stoi(byte, nullptr, 16)));  // Convert hex to int
    }

    std::cout << "Parsed MAC address bytes: ";
    for (uint8_t b : mac_bytes) {
        std::cout << std::hex << static_cast<int>(b) << " ";
    }
    std::cout << std::endl;
    return mac_bytes;
}

void test(std::string &mac)
{
    std::cout << mac << std::endl;
}

