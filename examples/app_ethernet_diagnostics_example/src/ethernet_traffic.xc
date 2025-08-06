// Copyright 2013-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <debug_print.h>
#include <xclib.h>
#include <stdint.h>
#include <string.h>

// Library headers
#include "ethernet.h"

#define PACKET_FOR_US       1
#define PACKET_NULL         0
#define PACKET_FOR_OTHER    -1
#define PACKET_CHECK_FAILED -2

#define ETH_FRAME_TYPE_ARP  0x0806
#define ETH_FRAME_TYPE_IP   0x0800

/* Network to Host byte-ordered short */
#define NTOHS(array, idx) ((unsigned short)((array[idx] << 8) | array[idx + 1]))

#define DST_MAC_IDX         0
#define SRC_MAC_IDX         6
#define ETH_TYPE_IDX        12
#define ETH_FRAME_HDR_SIZE  14
#define ETH_PACKET_MIN_SIZE 64

#define ARP_HW_TYPE_IDX     14
#define ARP_PROTO_TYPE_IDX  16
#define ARP_HW_LEN_IDX      18
#define ARP_PROTO_LEN_IDX   19
#define ARP_OPCODE_IDX      20
#define ARP_SENDER_MAC_IDX  22
#define ARP_SENDER_IP_IDX   28
#define ARP_TARGET_MAC_IDX  32
#define ARP_TARGET_IP_IDX   38
#define ARP_HEADER_END      42 // (ARP_TARGET_IP_IDX + IP_ADDR_SIZE)

#define IP_VERSION_IDX      14
#define IP_TOS_IDX          15
#define IP_TOTAL_LEN_IDX    16
#define IP_ID_IDX           18
#define IP_FLAGS_IDX        20
#define IP_TTL_IDX          22
#define IP_PROTOCOL_IDX     23
#define IP_CHECKSUM_IDX     24
#define IP_SRC_ADDR_IDX     26
#define IP_DST_ADDR_IDX     30
#define IP_HEADER_LEN       20 // (IP_DST_ADDR_IDX + IP_ADDR_SIZE - IP_VERSION_IDX)

#define ICMP_TYPE_CODE_IDX  34
#define ICMP_CHECKSUM_IDX   36
#define ICMP_ID_IDX         38
#define ICMP_SEQ_IDX        40
#define ICMP_DATA_IDX       42
#define ICMP_HEADER_LEN     8 // (ICMP_DATA_IDX - ICMP_TYPE_CODE_IDX)

#define UDP_SRC_PORT_IDX    34
#define UDP_DST_PORT_IDX    36
#define UDP_LENGTH_IDX      38
#define UDP_CHECKSUM_IDX    40
#define UDP_DATA_IDX        42

#define IP_ADDR_SIZE        4
#define IPv6_ADDR_SIZE      16

// IPv4 protocol type
#define IP_V6_HOP_PROTOCOL    0x00
#define IP_ICMP_PROTOCOL      0x01
#define IP_TCP_PROTOCOL       0x06
#define IP_UDP_PROTOCOL       0x11

static const unsigned char eth_arp_type[] = {
  0x08, 0x06, // Ethernet type: ARP
};

static const unsigned char eth_ip_type[] = {
  0x08, 0x00, // Ethernet type: IP
};

static unsigned char arp_body[] = {
  0x00, 0x01, // Hardware type: Ethernet
  0x08, 0x00, // Protocol type: IPv4
  0x06, 0x04, // Hardware size: 6 bytes,
};

static unsigned char arp_reply[] = {
  0x00, 0x02, // Opcode: reply
};

static unsigned char arp_request[] = {
  0x00, 0x01, // Opcode: request
};

static unsigned char icmp_echo_request[] = {
  0x08, 0x00, // ICMP type: echo request
};

// Calculate 16 bit checksum for IP header
// The checksum is calculated over the 16-bit words of the header.
//
// Calling this on a received packet this will return 0 if the checksum is correct,
// or a non-zero value if the checksum is incorrect.
// Calling this on a packet to be sent, set the checksum to 0 before calling this
// and then the result of this will provide the checksum to send.
static unsigned short checksum_ip(const unsigned char frame[34])
{
  unsigned accum1 = 0;
  unsigned accum2 = 0;
  for (int i = IP_VERSION_IDX; i < (IP_DST_ADDR_IDX + IP_ADDR_SIZE); i += 2)
  {
    accum1 += frame[i];
    accum2 += frame[i + 1];
  }

  unsigned accum = accum1 + (accum2 << 8);

  // Fold in carry into 16bits
  accum = (accum & 0xFFFF) + (accum >> 16);
  unsigned extra_carry = (accum >> 16);
  if (extra_carry)
  {
    accum += extra_carry;
  }
  accum = byterev(~accum) >> 16;

  return accum;
}

static void debug_ethernet_frame(unsigned char rxbuf[])
{
  debug_printf("- Ethernet source: %02X:%02X:%02X:%02X:%02X:%02X,", 
               rxbuf[SRC_MAC_IDX],
               rxbuf[SRC_MAC_IDX + 1],
               rxbuf[SRC_MAC_IDX + 2],
               rxbuf[SRC_MAC_IDX + 3],
               rxbuf[SRC_MAC_IDX + 4],
               rxbuf[SRC_MAC_IDX + 5]);

  debug_printf("   Ethernet destination: %02X:%02X:%02X:%02X:%02X:%02X,",
                rxbuf[DST_MAC_IDX],
                rxbuf[DST_MAC_IDX + 1],
                rxbuf[DST_MAC_IDX + 2],
                rxbuf[DST_MAC_IDX + 3],
                rxbuf[DST_MAC_IDX + 4],
                rxbuf[DST_MAC_IDX + 5]);

  debug_printf("   Ethernet type: ");
  if (memcmp(&rxbuf[ETH_TYPE_IDX], eth_arp_type, sizeof(eth_arp_type)) == 0)
  {
    debug_printf("ARP ");

  } else if (memcmp(&rxbuf[ETH_TYPE_IDX], eth_ip_type, sizeof(eth_ip_type)) == 0) {
    debug_printf("IP ");

  } else {
    debug_printf("Unknown ");
  }
  debug_printf("(0x%04X)\n", NTOHS(rxbuf, ETH_TYPE_IDX));
}

// Check if the received packet is an ARP request for our IP address
// Returns 1 if it is an ARP request, 0 if not, and -1 if it is an ARP request for another IP address
static int is_arp_packet(const unsigned char rxbuf[nbytes],
                         unsigned nbytes,
                         const unsigned char own_ip_addr[4])
{
  if (memcmp(&rxbuf[ETH_TYPE_IDX], eth_arp_type, sizeof(eth_arp_type)) != 0)
    return PACKET_NULL;

  debug_printf("\n-------------------\n");
  debug_printf("ARP packet received\n");

  if (memcmp(&rxbuf[ARP_HW_TYPE_IDX], arp_body, sizeof(arp_body)) != 0)
  {
    debug_printf("Invalid htype_ptype_hlen\n");
    return PACKET_CHECK_FAILED;
  }
  if (memcmp(&rxbuf[ARP_OPCODE_IDX], arp_request, sizeof(arp_request)) != 0)
  {
    debug_printf("Not a request\n");
    return PACKET_CHECK_FAILED;
  }
  if (memcmp(&rxbuf[ARP_TARGET_IP_IDX], own_ip_addr, IP_ADDR_SIZE) != 0)
  {
    return PACKET_FOR_OTHER;
  }

  return PACKET_FOR_US;
}

static void debug_arp_request(unsigned char rxbuf[])
{
  if (memcmp(&rxbuf[ARP_OPCODE_IDX], arp_request, sizeof(arp_request)) == 0)
  {
    debug_printf("- An ARP request\n");
  }
  debug_printf("- ARP hardware: %d, protocol: 0x%04X, length: %d\n",
               NTOHS(rxbuf, ARP_HW_TYPE_IDX), NTOHS(rxbuf, ARP_PROTO_TYPE_IDX), rxbuf[ARP_HW_LEN_IDX]);

  debug_printf("- ARP source: %02X:%02X:%02X:%02X:%02X:%02X,\tIP: %d.%d.%d.%d\n", 
                rxbuf[ARP_SENDER_MAC_IDX],
                rxbuf[ARP_SENDER_MAC_IDX + 1],
                rxbuf[ARP_SENDER_MAC_IDX + 2],
                rxbuf[ARP_SENDER_MAC_IDX + 3],
                rxbuf[ARP_SENDER_MAC_IDX + 4],
                rxbuf[ARP_SENDER_MAC_IDX + 5],
                rxbuf[ARP_SENDER_IP_IDX],
                rxbuf[ARP_SENDER_IP_IDX + 1],
                rxbuf[ARP_SENDER_IP_IDX + 2], 
                rxbuf[ARP_SENDER_IP_IDX + 3]);

  debug_printf("- ARP target: %02X:%02X:%02X:%02X:%02X:%02X,\tIP: %d.%d.%d.%d\n",
                rxbuf[ARP_TARGET_MAC_IDX],
                rxbuf[ARP_TARGET_MAC_IDX + 1],
                rxbuf[ARP_TARGET_MAC_IDX + 2],
                rxbuf[ARP_TARGET_MAC_IDX + 3],
                rxbuf[ARP_TARGET_MAC_IDX + 4],
                rxbuf[ARP_TARGET_MAC_IDX + 5],
                rxbuf[ARP_TARGET_IP_IDX],
                rxbuf[ARP_TARGET_IP_IDX + 1],
                rxbuf[ARP_TARGET_IP_IDX + 2],
                rxbuf[ARP_TARGET_IP_IDX + 3]);
}

static int build_arp_response(unsigned char rxbuf[ETH_PACKET_MIN_SIZE],
                              unsigned char txbuf[ETH_PACKET_MIN_SIZE],
                              const unsigned char own_mac_addr[MACADDR_NUM_BYTES],
                              const unsigned char own_ip_addr[IP_ADDR_SIZE])
{
  memcpy(&txbuf[DST_MAC_IDX], &rxbuf[ARP_SENDER_MAC_IDX], MACADDR_NUM_BYTES);
  memcpy(&txbuf[SRC_MAC_IDX], own_mac_addr, MACADDR_NUM_BYTES);
  memcpy(&txbuf[ETH_TYPE_IDX], eth_arp_type, sizeof(eth_arp_type));

  memcpy(&txbuf[ARP_HW_TYPE_IDX], arp_body, sizeof(arp_body));
  memcpy(&txbuf[ARP_OPCODE_IDX], arp_reply, sizeof(arp_reply));

  memcpy(&txbuf[ARP_SENDER_MAC_IDX], own_mac_addr, MACADDR_NUM_BYTES);
  memcpy(&txbuf[ARP_SENDER_IP_IDX], own_ip_addr, IP_ADDR_SIZE);

  memcpy(&txbuf[ARP_TARGET_MAC_IDX], &rxbuf[ARP_SENDER_MAC_IDX], MACADDR_NUM_BYTES);
  memcpy(&txbuf[ARP_TARGET_IP_IDX], &rxbuf[ARP_SENDER_IP_IDX], IP_ADDR_SIZE);

  memset(&txbuf[ARP_HEADER_END], 0, (ETH_PACKET_MIN_SIZE - ARP_HEADER_END));

  return ETH_PACKET_MIN_SIZE;
}

static void process_arp_packet(unsigned char rxbuf[],
                               unsigned nbytes,
                               client ethernet_tx_if tx,
                               const unsigned char own_mac_addr[MACADDR_NUM_BYTES],
                               const unsigned char own_ip_addr[IP_ADDR_SIZE])
{
  int is_arp = is_arp_packet(rxbuf, nbytes, own_ip_addr);
  if (is_arp == PACKET_FOR_US)
  {
    unsigned char txbuf[ETHERNET_MAX_PACKET_SIZE];
    
    debug_ethernet_frame(rxbuf);
    debug_arp_request(rxbuf);

    int len = build_arp_response(rxbuf, txbuf, own_mac_addr, own_ip_addr);
    tx.send_packet(txbuf, len, ETHERNET_ALL_INTERFACES);
    debug_printf("ARP response sent\n");
  }
  else if (is_arp == PACKET_FOR_OTHER)
  {
    debug_ethernet_frame(rxbuf);
    debug_arp_request(rxbuf);
  }
  else if (is_arp == PACKET_CHECK_FAILED)
  {
    debug_printf("Invalid ARP packet\n");
    debug_ethernet_frame(rxbuf);
    debug_arp_request(rxbuf);
  }
}

// Check if the received packet is an IP packet for our IP address
// Returns 1 if it is an IP packet for our address, 0 if not, 
// and -1 if it is an IP packet for another IP address
static int is_ip_packet(const unsigned char rxbuf[nbytes],
                                unsigned nbytes,
                                const unsigned char own_ip_addr[4])
{
  if (memcmp(&rxbuf[ETH_TYPE_IDX], eth_ip_type, sizeof(eth_ip_type)) != 0)
    return PACKET_NULL;

  debug_printf("\n-------------------\n");
  debug_printf("IPv4 packet received\n");

  unsigned totallen = NTOHS(rxbuf, IP_TOTAL_LEN_IDX);
  if (nbytes > 60 && nbytes != totallen + ETH_FRAME_HDR_SIZE)
  {
    debug_printf("Invalid size (nbytes: %d, totallen: %d)\n", nbytes, totallen + ETH_FRAME_HDR_SIZE);
    return PACKET_CHECK_FAILED;
  }
  if (checksum_ip(rxbuf) != 0)
  {
    debug_printf("Bad checksum\n");
    return PACKET_CHECK_FAILED;
  }

  if (memcmp(&rxbuf[IP_DST_ADDR_IDX], own_ip_addr, IP_ADDR_SIZE) != 0)
  {
    debug_printf("Not for us\n");
    return PACKET_FOR_OTHER;
  }

  return PACKET_FOR_US;
}

static void debug_icmp_packet(unsigned char rxbuf[], int datalen)
{
  if (memcmp(&rxbuf[ICMP_TYPE_CODE_IDX], icmp_echo_request, sizeof(icmp_echo_request)) == 0)
  {
    debug_printf("- An ICMP echo request\n");
  }
  debug_printf("- ICMP type: %d\n", rxbuf[ICMP_TYPE_CODE_IDX]);
  debug_printf("- ICMP code: %d\n", rxbuf[ICMP_TYPE_CODE_IDX + 1]);
  
  debug_printf("- ICMP checksum: 0x%04X\n", NTOHS(rxbuf, ICMP_CHECKSUM_IDX));

  debug_printf("- ICMP data: ");
  for (int i = 0; i < datalen; i++)
  {
    debug_printf("%02X ", rxbuf[ICMP_DATA_IDX + i]);
  }
  debug_printf("\n");
}

static void debug_udp_packet(unsigned char rxbuf[])
{
  debug_printf("- UDP src port: %d, dst port: %d, length: %d, checksum: 0x%04X\n",
               NTOHS(rxbuf, UDP_SRC_PORT_IDX),
               NTOHS(rxbuf, UDP_DST_PORT_IDX),
               NTOHS(rxbuf, UDP_LENGTH_IDX),
               NTOHS(rxbuf, UDP_CHECKSUM_IDX));

  debug_printf("- UDP data: 0x%04X ...\n", NTOHS(rxbuf, UDP_DATA_IDX));
}

static void debug_ip_request(unsigned char rxbuf[])
{
  int totallen = NTOHS(rxbuf, IP_TOTAL_LEN_IDX);
  int datalen = totallen - (IP_HEADER_LEN + ICMP_HEADER_LEN);

  debug_printf("- IP version: 0x%02X, length: %d, checksum: 0x%04X, %s\n",
              rxbuf[IP_VERSION_IDX], totallen, NTOHS(rxbuf, IP_CHECKSUM_IDX), checksum_ip(rxbuf) ? "bad" : "ok");

  debug_printf("- IP source: %d.%d.%d.%d\n",
                rxbuf[IP_SRC_ADDR_IDX],
                rxbuf[IP_SRC_ADDR_IDX + 1],
                rxbuf[IP_SRC_ADDR_IDX + 2],
                rxbuf[IP_SRC_ADDR_IDX + 3]);

  debug_printf("- IP destination: %d.%d.%d.%d\n",
                rxbuf[IP_DST_ADDR_IDX],
                rxbuf[IP_DST_ADDR_IDX + 1],
                rxbuf[IP_DST_ADDR_IDX + 2],
                rxbuf[IP_DST_ADDR_IDX + 3]);

  if (rxbuf[IP_PROTOCOL_IDX] == IP_ICMP_PROTOCOL)
  {
    debug_printf("ICMP packet received (0x%02X)\n", IP_PROTOCOL_IDX);
    debug_icmp_packet(rxbuf, datalen);
  }
  else if (rxbuf[IP_PROTOCOL_IDX] == IP_TCP_PROTOCOL)
  {
    debug_printf("TCP packet received (0x%02X)\n", IP_PROTOCOL_IDX);
  }
  else if (rxbuf[IP_PROTOCOL_IDX] == IP_UDP_PROTOCOL)
  {
    debug_printf("UDP packet received (0x%02X)\n", IP_PROTOCOL_IDX);
    debug_udp_packet(rxbuf);
  }
  else
  {
    debug_printf("Unknown IP protocol (0x%02X)\n", rxbuf[IP_PROTOCOL_IDX]);
  }
}

static void process_ip_packet(unsigned char rxbuf[],
                              unsigned nbytes,
                              const unsigned char own_ip_addr[IP_ADDR_SIZE])
{
  int is_ip = is_ip_packet(rxbuf, nbytes, own_ip_addr);

  if ((is_ip == PACKET_FOR_US) || (is_ip == PACKET_FOR_OTHER))
  {
    debug_ethernet_frame(rxbuf);
    debug_ip_request(rxbuf);
  }
  else if (is_ip == PACKET_CHECK_FAILED)
  {
    debug_printf("Invalid IP packet\n");
    debug_ethernet_frame(rxbuf);
    debug_ip_request(rxbuf);
  }
  else
  {
    debug_printf("\n\nDebug Other...\n");
    debug_ethernet_frame(rxbuf);
  }
}

[[combinable]]
void ethernet_traffic(client ethernet_cfg_if cfg,
                      client ethernet_rx_if rx,
                      client ethernet_tx_if tx,
                      const unsigned char ip_address[4],
                      const unsigned char mac_address[MACADDR_NUM_BYTES])
{
  ethernet_macaddr_filter_t macaddr_filter;

  size_t index = rx.get_index();
  cfg.set_macaddr(0, mac_address);

  memcpy(macaddr_filter.addr, mac_address, sizeof(mac_address));
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  // Add broadcast filter
  memset(macaddr_filter.addr, 0xff, MACADDR_NUM_BYTES);
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  // Only allow ARP and IP packets to the app
  cfg.add_ethertype_filter(index, ETH_FRAME_TYPE_ARP);
  cfg.add_ethertype_filter(index, ETH_FRAME_TYPE_IP);

  debug_printf("Diagnostic server started at MAC %x:%x:%x:%x:%x:%x, IP %d.%d.%d.%d\n",
                mac_address[0], mac_address[1], mac_address[2],
                mac_address[3], mac_address[4], mac_address[5],
                ip_address[0], ip_address[1], ip_address[2], ip_address[3]);

  while (1)
  {
    select {
    case rx.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);

      if (packet_info.type != ETH_DATA) {
        // convert ethernet_speed_t to Mbps
        int speed = 10;
        for (int i = 0; i < (int)rxbuf[1]; i++) {
          speed = speed * 10;
        }
        debug_printf("Link: %s, speed: %d Mbps\n", rxbuf[0] ? "up" : "down", speed);

      } else {
        // Data received

        int eth_type = NTOHS(rxbuf, ETH_TYPE_IDX);
        switch (eth_type) {
          case ETH_FRAME_TYPE_ARP:
            process_arp_packet(rxbuf, packet_info.len, tx, mac_address, ip_address);
            break;

          case ETH_FRAME_TYPE_IP:
            process_ip_packet(rxbuf, packet_info.len, ip_address);
            break;

          default:
            debug_printf("\nUnknown Ethernet frame type (0x%04X)\n", eth_type);
            break;
        }
      }
      break;
    }
  }
}
