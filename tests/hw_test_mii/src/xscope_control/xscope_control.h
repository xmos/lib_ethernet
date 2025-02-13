#ifndef __XSCOPE_CONTROL_H__
#define __XSCOPE_CONTROL_H__

#include <xs1.h>

enum {
    CMD_DEVICE_SHUTDOWN = 1,
    CMD_SET_DEVICE_MACADDR,
    CMD_SET_HOST_MACADDR,
    CMD_HOST_SET_DUT_TX_PACKETS,
    CMD_SET_DUT_RECEIVE,
    CMD_DEVICE_CONNECT
};

void xscope_control(chanend c_xscope, chanend c_clients[num_clients], static const unsigned num_clients);

#endif
