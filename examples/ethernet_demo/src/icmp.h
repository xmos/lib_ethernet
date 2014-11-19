#ifndef __icmp_h__
#define __icmp_h__
#include <ethernet.h>
#include <otp_board_info.h>


[[combinable]]
void icmp_server(client ethernet_if eth,
                 const unsigned char ip_address[4],
                 otp_ports_t &otp_ports);

#endif // __icmp_h__
