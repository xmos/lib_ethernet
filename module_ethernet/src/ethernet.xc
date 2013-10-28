#include "ethernet.h"

extends client interface ethernet_if : {

  extern inline void send_packet(client ethernet_if i,
                                 char packet[n], unsigned n, unsigned dst_port);

}
