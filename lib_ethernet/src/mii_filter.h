#ifndef __mii_filter_h__
#define __mii_filter_h__
#include "ethernet.h"
#include "mii_ethernet_conf.h"
#include "macaddr_filter.h"

unsafe void mii_ethernet_filter(streaming chanend c_data, chanend c_conf);

#endif // __mii_filter_h__
