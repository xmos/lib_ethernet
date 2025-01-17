// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __client_state_h__
#define __client_state_h__

#include "ethernet.h"
#include "default_ethernet_conf.h"
#include "mii_master.h"
#include "mii_filter.h"
#include "mii_buffering.h"
#include "mii_ts_queue.h"

#ifdef __XC__
extern "C" {
#endif

enum status_update_state_t {
  STATUS_UPDATE_IGNORING,
  STATUS_UPDATE_WAITING,
  STATUS_UPDATE_PENDING,
};

// Data structure to keep track of link layer status for receive clients.
typedef struct
{
  unsigned dropped_pkt_cnt;
  unsigned rd_index[NUM_ETHERNET_PORTS];
  unsigned wr_index[NUM_ETHERNET_PORTS];
  void *fifo[NUM_ETHERNET_PORTS][ETHERNET_RX_CLIENT_QUEUE_SIZE];
  int status_update_state[NUM_ETHERNET_PORTS];
  size_t num_etype_filters;
  int strip_vlan_tags;
  uint16_t etype_filters[ETHERNET_MAX_ETHERTYPE_FILTERS];
} rx_client_state_t;

// Data structure to keep track of link layer status for transmit clients.
typedef struct
{
  int requested_send_buffer_size;
  mii_packet_t *send_buffer[NUM_ETHERNET_PORTS];
  int has_outgoing_timestamp_info[NUM_ETHERNET_PORTS];
  unsigned outgoing_timestamp[NUM_ETHERNET_PORTS];
  int dst_port;
} tx_client_state_t;

#ifdef __XC__
} // extern "C"
#endif

#ifdef __XC__

void init_rx_client_state(rx_client_state_t client_state[n], unsigned n);
void init_tx_client_state(tx_client_state_t client_state[n], unsigned n);

#endif


#endif // __client_state_h__
