// Copyright 2013-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <debug_print.h>
#include <xclib.h>
#include <stdint.h>
#include <ethernet.h>
#include <string.h>

#define ETH_FRAME_TYPE_ARP 0x0806
#define ETH_FRAME_TYPE_IP  0x0800

/* Network to Host byte-ordered short */
#define NTOHS(array, idx) ((unsigned short)((array[idx] << 8) | array[idx + 1]))
/* Host to Network byte-ordered short */
#define HTONS(array, idx, value) \
do { \
    array[idx] = value >> 8; \
    array[idx + 1] = value & 0xFF; \
} while (0)

#define DST_MAC_IDX         0
#define SRC_MAC_IDX         6
#define ETH_TYPE_IDX        12
#define ETH_FRAME_MIN_SIZE  64

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

#define IP_ADDR_SIZE        4

#define IP_ICMP_PROTOCOL    0x01

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

static unsigned char icmp_echo_reply[] = {
  0x00, 0x00, // ICMP type: echo reply
};

static unsigned char ip_icmp_ping_version[] = {
  0x45, 0x00, // IP version and header length
};

static unsigned char ip_body[] = {
  0x00, 0x00, // Identification and flags
  0x00, 0x00, // Fragment offset
  0x40, 0x01, // TTL and protocol (ICMP)
};

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


static int build_arp_response(unsigned char rxbuf[ETH_FRAME_MIN_SIZE],
                              unsigned char txbuf[ETH_FRAME_MIN_SIZE],
                              const unsigned char own_mac_addr[MACADDR_NUM_BYTES],
                              const unsigned char own_ip_addr[IP_ADDR_SIZE])
{
  memcpy(&txbuf[DST_MAC_IDX], &rxbuf[22], MACADDR_NUM_BYTES);
  memcpy(&txbuf[SRC_MAC_IDX], own_mac_addr, MACADDR_NUM_BYTES);
  memcpy(&txbuf[ETH_TYPE_IDX], eth_arp_type, sizeof(eth_arp_type));

  memcpy(&txbuf[ARP_HW_TYPE_IDX], arp_body, sizeof(arp_body));
  memcpy(&txbuf[ARP_OPCODE_IDX], arp_reply, sizeof(arp_reply));

  memcpy(&txbuf[ARP_SENDER_MAC_IDX], own_mac_addr, MACADDR_NUM_BYTES);
  memcpy(&txbuf[ARP_SENDER_IP_IDX], own_ip_addr, IP_ADDR_SIZE);

  memcpy(&txbuf[ARP_TARGET_MAC_IDX], &rxbuf[22], MACADDR_NUM_BYTES);
  memcpy(&txbuf[ARP_TARGET_IP_IDX], &rxbuf[28], IP_ADDR_SIZE);

  memset(&txbuf[ARP_HEADER_END], 0, (ETH_FRAME_MIN_SIZE - ARP_HEADER_END));

  return ETH_FRAME_MIN_SIZE;
}

static int is_valid_arp_packet(const unsigned char rxbuf[nbytes],
                               unsigned nbytes,
                               const unsigned char own_ip_addr[4])
{
  if (memcmp(&rxbuf[ETH_TYPE_IDX], eth_arp_type, sizeof(eth_arp_type)) != 0)
    return 0;

  debug_printf("ARP packet received\n");

  if (memcmp(&rxbuf[ARP_HW_TYPE_IDX], arp_body, sizeof(arp_body)) != 0)
  {
    debug_printf("Invalid htype_ptype_hlen\n");
    return 0;
  }
  if (memcmp(&rxbuf[ARP_OPCODE_IDX], arp_request, sizeof(arp_request)) != 0)
  {
    debug_printf("Not a request\n");
    return 0;
  }
  if (memcmp(&rxbuf[ARP_TARGET_IP_IDX], own_ip_addr, IP_ADDR_SIZE) != 0)
  {
    debug_printf("Not for us\n");
    return 0;
  }

  return 1;
}

static int build_icmp_response(unsigned char rxbuf[], unsigned char txbuf[],
                               const unsigned char own_mac_addr[MACADDR_NUM_BYTES],
                               const unsigned char own_ip_addr[4])
{
  int totallen = NTOHS(rxbuf, IP_TOTAL_LEN_IDX);
  int datalen = totallen - (IP_HEADER_LEN + ICMP_HEADER_LEN);

  memcpy(&txbuf[DST_MAC_IDX], &rxbuf[SRC_MAC_IDX], MACADDR_NUM_BYTES);
  memcpy(&txbuf[SRC_MAC_IDX], own_mac_addr, MACADDR_NUM_BYTES);
  memcpy(&txbuf[ETH_TYPE_IDX], eth_ip_type, sizeof(eth_ip_type));

  memcpy(&txbuf[IP_VERSION_IDX], ip_icmp_ping_version, sizeof(ip_icmp_ping_version));
  txbuf[IP_TOTAL_LEN_IDX] = (totallen >> 8) & 0xFF;
  txbuf[IP_TOTAL_LEN_IDX + 1] = totallen & 0xFF;

  memcpy(&txbuf[IP_ID_IDX], ip_body, sizeof(ip_body));

  memset(&txbuf[IP_CHECKSUM_IDX], 0, 2);

  memcpy(&txbuf[IP_SRC_ADDR_IDX], own_ip_addr, IP_ADDR_SIZE);
  memcpy(&txbuf[IP_DST_ADDR_IDX], &rxbuf[IP_SRC_ADDR_IDX], IP_ADDR_SIZE);

  unsigned ip_checksum = checksum_ip(txbuf);
  HTONS(txbuf, IP_CHECKSUM_IDX, ip_checksum);

  memcpy(&txbuf[ICMP_TYPE_CODE_IDX], icmp_echo_reply, sizeof(icmp_echo_reply));
  memcpy(&txbuf[ICMP_ID_IDX], &rxbuf[ICMP_ID_IDX], 4);
  memcpy(&txbuf[ICMP_DATA_IDX], &rxbuf[ICMP_DATA_IDX], datalen);

  unsigned icmp_checksum = NTOHS(rxbuf, ICMP_CHECKSUM_IDX);
  // Calculate ICMP checksum, 0x800 adjusts for change in type between request and reply
  icmp_checksum = (icmp_checksum + 0x0800);
  icmp_checksum += (icmp_checksum >> 16);
  HTONS(txbuf, ICMP_CHECKSUM_IDX, icmp_checksum);

  int pad;
  for (pad = (ICMP_DATA_IDX + datalen); pad < ETH_FRAME_MIN_SIZE; pad++)
  {
    txbuf[pad] = 0x00;
  }
  return pad;
}


static int is_valid_icmp_packet(const unsigned char rxbuf[nbytes],
                                unsigned nbytes,
                                const unsigned char own_ip_addr[4])
{
  if ((memcmp(&rxbuf[ETH_TYPE_IDX], eth_ip_type, sizeof(eth_ip_type)) != 0) || (rxbuf[IP_PROTOCOL_IDX] != IP_ICMP_PROTOCOL))
    return 0;

  debug_printf("ICMP packet received\n");

  if (memcmp(&rxbuf[IP_VERSION_IDX], ip_icmp_ping_version, sizeof(ip_icmp_ping_version)) != 0)
  {
    debug_printf("Invalid IP version\n");
    return 0;
  }
  if (memcmp(&rxbuf[ICMP_TYPE_CODE_IDX], icmp_echo_request, sizeof(icmp_echo_request)) != 0)
  {
    debug_printf("Invalid type_code\n");
    return 0;
  }
  if (memcmp(&rxbuf[IP_DST_ADDR_IDX], own_ip_addr, IP_ADDR_SIZE) != 0)
  {
    debug_printf("Not for us\n");
    return 0;
  }

  unsigned totallen = NTOHS(rxbuf, IP_TOTAL_LEN_IDX);
  if (nbytes > 60 && nbytes != totallen + 14)
  {
    debug_printf("Invalid size (nbytes:%d, totallen:%d)\n", nbytes, totallen+14);
    return 0;
  }
  if (checksum_ip(rxbuf) != 0)
  {
    debug_printf("Bad checksum\n");
    return 0;
  }

  return 1;
}

[[combinable]]
void icmp_server(client ethernet_cfg_if cfg,
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

  debug_printf("ICMP server started at MAC %x:%x:%x:%x:%x:%x, IP %d.%d.%d.%d\n",
                mac_address[0], mac_address[1], mac_address[2],
                mac_address[3], mac_address[4], mac_address[5],
                ip_address[0], ip_address[1], ip_address[2], ip_address[3]);

  while (1)
  {
    select {
    case rx.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      unsigned char txbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);

      if (packet_info.type != ETH_DATA)
      {
        debug_printf("Link: %s, speed %d\n", rxbuf[0] ? "up" : "down", rxbuf[1]);
      }
      else if (is_valid_arp_packet(rxbuf, packet_info.len, ip_address))
      {
        int len = build_arp_response(rxbuf, txbuf, mac_address, ip_address);
        tx.send_packet(txbuf, len, ETHERNET_ALL_INTERFACES);
        debug_printf("ARP response sent\n");
      }
      else if (is_valid_icmp_packet(rxbuf, packet_info.len, ip_address))
      {
        int len = build_icmp_response(rxbuf, txbuf, mac_address, ip_address);
        tx.send_packet(txbuf, len, ETHERNET_ALL_INTERFACES);
        debug_printf("ICMP response sent\n");
      }
      break;
    }
  }
}
