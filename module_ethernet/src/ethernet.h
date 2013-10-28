#ifndef __ethernet__h__
#define __ethernet__h__

#ifdef __ethernet_conf_h_exists__
#include "ethernet_conf.h"
#endif

typedef enum {
  ETH_DATA,
  ETH_IF_STATUS,
  ETH_OUTGOING_TIMESTAMP_INFO,
  ETH_SEND_BUFFER_READY,
  ETH_NO_DATA
} eth_packet_type_t;

#define ETHERNET_ALL_INTERFACES  (-1)

#define ETHERNET_MAX_PACKET_SIZE (1518)

typedef enum ethernet_link_state_t {
  ETHERNET_LINK_DOWN,
  ETHERNET_LINK_UP
} ethernet_link_state_t;


typedef struct ethernet_packet_info_t {
  eth_packet_type_t type;
  int len;
  unsigned timestamp;
  unsigned src_port;
} ethernet_packet_info_t;


#ifdef __XC__

typedef interface ethernet_config_if {
  void set_link_state(int, ethernet_link_state_t);
} ethernet_config_if;

typedef interface ethernet_filter_if {
  unsigned do_filter(char packet[len], unsigned len);
} ethernet_filter_if;

typedef interface ethernet_if {

  void get_macaddr(unsigned char mac_address[6]);

  void set_receive_filter_mask(unsigned mask);

  void init_send_packet(unsigned n, unsigned dst_port);
  void complete_send_packet(char packet[n], unsigned n,
                            unsigned dst_port);


  [[notification]] slave void packet_ready();
  [[clears_notification]] void get_packet(ethernet_packet_info_t &desc,
                                          char data[n],
                                          unsigned n);
} ethernet_if;

extends client interface ethernet_if : {

  inline void send_packet(client ethernet_if i, char packet[n], unsigned n,
                          unsigned dst_port) {
    i.init_send_packet(n, dst_port);
    i.complete_send_packet(packet, n, dst_port);
  }

}

[[distributable]]
void arp_ip_filter(server ethernet_filter_if i_filter);

#endif

#endif // __ethernet__h__
