// Copyright 2013-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <debug_print.h>
#include <xclib.h>
#include <stdint.h>
#include <stdlib.h>
#include <ethernet.h>
#include <otp_board_info.h>
#include <string.h>
#include <print.h>


#define MAX_PACKET_BYTES (6 + 6 + 2 + 1500) 
#define HOST_READY_TO_RECEIVE_TIME_MS 2000 // how long it takes for host to start capture thread

typedef struct
{
  unsigned current_seq_id;
  unsigned prev_seq_id;
  unsigned ifg;
}seq_id_pair_t;

void test_tx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 unsigned client_num,
                 chanend c_xscope_control)
{
  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < MACADDR_NUM_BYTES; i++)
    macaddr_filter.addr[i] = i+client_num;

  size_t index = rx.get_index();
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  // Add broadcast filter
  memset(macaddr_filter.addr, 0xff, MACADDR_NUM_BYTES);
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  cfg.add_ethertype_filter(index, 0x2222);


  uint8_t broadcast[MACADDR_NUM_BYTES];
  for(int i=0; i<MACADDR_NUM_BYTES; i++)
  {
    broadcast[i] = 0xff;
  }
 


  int num_packets_to_send = 100000;
  int packet_length = MAX_PACKET_BYTES;
  debug_printf("DUT preparing to send %d packets of length %d\n", num_packets_to_send, packet_length);

  c_xscope_control <: 1; // Indicate ready

  // wait for all clear from host app
  int cmd;
  c_xscope_control :> cmd;
  debug_printf("Got OK from host LP: %d\n", cmd);

  delay_milliseconds(HOST_READY_TO_RECEIVE_TIME_MS);


  // uint8_t tx_target_mac[MACADDR_NUM_BYTES] = {0xa4, 0xae, 0x12, 0x77, 0x86, 0x97};
  uint8_t tx_source_mac[MACADDR_NUM_BYTES] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05};
  uint8_t tx_target_mac[MACADDR_NUM_BYTES] = {0x4c, 0xe1, 0x73, 0x47, 0xcc, 0xbe};
  uint8_t ether_type[2] = {0x22, 0x22};

  char data[MAX_PACKET_BYTES] = {0};
  memcpy(&data[0], tx_target_mac, sizeof(tx_target_mac));
  memcpy(&data[6], tx_source_mac, sizeof(tx_source_mac));
  memcpy(&data[12], ether_type, sizeof(ether_type));


  const int length = MAX_PACKET_BYTES;

  for(int i = 0; i < num_packets_to_send; i++){
    memcpy(&data[14], &i, sizeof(i));
    tx.send_packet(data, length, ETHERNET_ALL_INTERFACES);
    debug_printf("sent: %d\n", i);
  }

  c_xscope_control :> int _;
  debug_printf("Got shutdown from host LP\n");
  c_xscope_control <: 1; // Acknowledge shutdown completion
}



void test_tx_hp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 streaming chanend c_tx_hp,
                 chanend c_xscope_control){
  c_xscope_control <: 1; // Indicate ready
  debug_printf("test_tx_hp\n");

  // wait for all clear from host app
  int cmd;
  c_xscope_control :> cmd;
  debug_printf("Got OK from host HP: %d\n", cmd);

  delay_milliseconds(HOST_READY_TO_RECEIVE_TIME_MS);

  c_xscope_control :> int _;
  debug_printf("Got shutdown from host HP\n");
  c_xscope_control <: 1; // Indicate shutdown
}