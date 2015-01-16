#include "ethernet.h"

extends client interface ethernet_tx_if : {

  extern inline void send_packet(client ethernet_tx_if i,
                                 char packet[n], unsigned n, unsigned dst_port);

}
