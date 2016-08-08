// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#include "ethernet.h"
#include "mii_impl.h"

extends client interface ethernet_tx_if : {

  extern inline void send_packet(client ethernet_tx_if i,
                                 char packet[n], unsigned n, unsigned dst_port);
  extern inline unsigned send_timed_packet(client ethernet_tx_if i, char packet[n],
                                    unsigned n,
                                    unsigned ifnum);
}

// Create reference to this inline function so that there is at
// least one instance for linker
extern inline void mii_receive_hp_packet(streaming chanend c_rx_hp,
                                         char buf[],
                                         ethernet_packet_info_t &packet_info);
extern inline void mii_send_hp_packet(streaming chanend c_tx_hp,
                                      char packet[n],
                                      unsigned n,
                                      unsigned dst_port);

extern inline mii_unsafe_chanend mii_get_notification_chanend(mii_lite_data_t * unsafe p);

extern inline mii_unsafe_chanend mii_get_out_chanend(mii_lite_data_t * unsafe p);

extern inline void mii_packet_sent_(unsafe chanend c);

extern inline void mii_incoming_packet_(unsafe chanend c, mii_lite_data_t * unsafe p);

extern inline void ethernet_receive_hp_packet(streaming chanend c_rx_hp,
                                       char packet[],
                                       ethernet_packet_info_t &packet_info);

extern inline void ethernet_send_hp_packet(streaming chanend c_tx_hp,
                                    char packet[n],
                                    unsigned n,
                                    unsigned ifnum);
