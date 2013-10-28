#ifndef __mii_filter_h__
#define __mii_filter_h__
#include "ethernet.h"

void mii_ethernet_filter(const char mac_address[6],
                         streaming chanend c,
                         client interface ethernet_filter_if i_filter);

#endif // __mii_filter_h__
