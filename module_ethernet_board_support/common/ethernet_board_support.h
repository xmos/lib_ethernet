#ifndef __ethernet_board_support_h__
#define __ethernet_board_support_h__

#include "platform.h"

// This header file provides default port intializers for the ethernet
// for XMOS development boards, it gets the board specific defines from
// ethernet_board_conf.h which is in a board specific directory in this module
// (e.g. module_ethernet_board_support/XR-AVB-LC-BRD)

#ifdef __ethernet_board_conf_h_exists__
#include "ethernet_board_conf.h"
#else
#warning "Using ethernet_board_conf.h but TARGET is not set to a board that module_ethernet_board_support uses"
#endif

#endif // __ethernet_board_support_h__
