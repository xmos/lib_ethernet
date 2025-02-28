// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include "client_state.h"

void init_rx_client_state(rx_client_state_t client_state[n], unsigned n)
{
  for (unsigned i = 0; i < n; i ++) {
    client_state[i].dropped_pkt_cnt = 0;
    client_state[i].rd_index = 0;
    client_state[i].wr_index = 0;
    client_state[i].status_update_state = STATUS_UPDATE_WAITING;
    client_state[i].num_etype_filters = 0;
    client_state[i].strip_vlan_tags = 0;
  }
}

void init_tx_client_state(tx_client_state_t client_state[n], unsigned n)
{
  for (unsigned i = 0; i < n; i ++) {
    client_state[i].requested_send_buffer_size = 0;
    client_state[i].send_buffer = null;
    client_state[i].has_outgoing_timestamp_info = 0;
  }
}
