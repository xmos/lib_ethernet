#ifndef __mii_filter_h__
#define __mii_filter_h__
#include "ethernet.h"
#include "mii_ethernet_conf.h"

unsafe void mii_ethernet_filter(const char mac_address[6],
                                streaming chanend c,
                                client interface ethernet_filter_callback_if i_filter);

#endif // __mii_filter_h__
