// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __XSCOPE_CMD_HANDLER_H__
#define __XSCOPE_CMD_HANDLER_H__

#include <xs1.h>
#include "ethernet.h"

typedef struct
{
  unsigned char source_mac_addr[MACADDR_NUM_BYTES];
  unsigned char target_mac_addr[MACADDR_NUM_BYTES];
  unsigned done;
  unsigned receiving;
  unsigned num_tx_packets;
  unsigned tx_packet_len;
  unsigned qav_bw_bps;
}client_state_t;

typedef struct
{
  unsigned client_num;
  unsigned client_index;
  unsigned is_hp;
}client_cfg_t;

select xscope_cmd_handler(chanend c_xscope_control, client_cfg_t &client_cfg, client ethernet_cfg_if cfg, client_state_t &client_state);

#endif
