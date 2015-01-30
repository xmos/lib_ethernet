#include "ethernet.h"

extends client interface ethernet_tx_if : {

  extern inline void send_packet(client ethernet_tx_if i,
                                 char packet[n], unsigned n, unsigned dst_port);

}

// Create reference to this inline function so that there is at
// least one instance for linker
extern inline void mii_receive_hp_packet(streaming chanend c_rx_hp,
                                         unsigned char *buf,
                                         ethernet_packet_info_t &packet_info);
