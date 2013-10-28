#ifndef __icmp_h__
#define __icmp_h__
#include "ethernet.h"

[[combinable]]
void icmp_server(client ethernet_if eth, const unsigned char ip_address[4]);

#endif // __icmp_h__
