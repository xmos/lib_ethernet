// Copyright 2013-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <debug_print.h>
#include <xclib.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ethernet.h>
#include <otp_board_info.h>
#include <string.h>
#include <print.h>
#include "xscope_control.h"


#define MAX_PACKET_BYTES (6 + 6 + 2 + 1500) 
#define HOST_READY_TO_RECEIVE_TIME_MS 2000 // how long it takes for host to start capture thread

typedef struct
{
  unsigned current_seq_id;
  unsigned prev_seq_id;
  unsigned ifg;
}seq_id_pair_t;

{unsigned, unsigned} get_config_from_host(chanend c_xscope_control,
                                          uint8_t tx_source_mac[MACADDR_NUM_BYTES],
                                          uint8_t tx_target_mac[MACADDR_NUM_BYTES])
{
  unsigned arg1 = 0 , arg2 = 0;
  int running = 1;

  while(running){
    select{
      case c_xscope_control :> int cmd: // Shutdown received over xscope
        if(cmd == CMD_SET_DEVICE_MACADDR)
        {
          debug_printf("Received CMD_SET_DEVICE_MACADDR command\n");
          for(int i=0; i<MACADDR_NUM_BYTES; i++)
          {
            c_xscope_control :> tx_source_mac[i];
          }
          c_xscope_control <: 1; // Acknowledge
        }
        else if(cmd == CMD_SET_HOST_MACADDR)
        {
          debug_printf("Received CMD_SET_HOST_MACADDR command\n");
          for(int i=0; i<MACADDR_NUM_BYTES; i++)
          {
            c_xscope_control :> tx_target_mac[i];
          }
          c_xscope_control <: 1; // Acknowledge
        }
        else if(cmd == CMD_HOST_SET_DUT_TX_PACKETS)
        {
          c_xscope_control :> arg1;
          c_xscope_control :> arg2;
          c_xscope_control <: 1; // Acknowledge
          running = 0;
        }
        break;
    } // select
  } // running
  return {arg1, arg2};
}






void test_tx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 unsigned client_num,
                 chanend c_xscope_control,
                 chanend c_lp_done)
{
  c_xscope_control <: 1; // Indicate ready

  // data structures needed for packet
  uint8_t tx_source_mac[MACADDR_NUM_BYTES] = {0};
  uint8_t tx_target_mac[MACADDR_NUM_BYTES] = {0};
  unsigned num_packets_to_send = 0, packet_length = 0;
  uint16_t ether_type = 0x2222;

  // get config
  {num_packets_to_send, packet_length} = get_config_from_host(c_xscope_control, tx_source_mac, tx_target_mac);
  debug_printf("LP got commands num packets: %u length: %u\n", num_packets_to_send, packet_length);

  // Ethernet packet setup
  char data[MAX_PACKET_BYTES] = {0};
  memcpy(&data[0], tx_target_mac, sizeof(tx_target_mac));
  memcpy(&data[6], tx_source_mac, sizeof(tx_source_mac));
  memcpy(&data[12], &ether_type, sizeof(ether_type));

  // Send packets
  for(int i = 0; i < num_packets_to_send; i++){
    memcpy(&data[14], &i, sizeof(i)); // sequence ID
    tx.send_packet(data, packet_length, ETHERNET_ALL_INTERFACES);
  }

  c_lp_done <: 0; // Break HP


  c_xscope_control :> int _;
  debug_printf("Got shutdown from host LP\n");
  c_xscope_control <: 1; // Acknowledge shutdown completion
}



void test_tx_hp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 streaming chanend c_tx_hp,
                 chanend c_xscope_control,
                 chanend c_lp_done){
  c_xscope_control <: 1; // Indicate ready

   // data structures needed for packet
  uint8_t tx_source_mac[MACADDR_NUM_BYTES] = {0};
  uint8_t tx_target_mac[MACADDR_NUM_BYTES] = {0};
  unsigned bandwidth_bps = 0, packet_length = 0;
  uint16_t ether_type = 0x2222;

  // get config
  {bandwidth_bps, packet_length} = get_config_from_host(c_xscope_control, tx_source_mac, tx_target_mac);
  debug_printf("HP got commands bandwidth %u packet length %u from host LP\n", bandwidth_bps, packet_length);

  // Ethernet packet setup
  char data[MAX_PACKET_BYTES] = {0};
  memcpy(&data[0], tx_target_mac, sizeof(tx_target_mac));
  memcpy(&data[6], tx_source_mac, sizeof(tx_source_mac));
  memcpy(&data[12], &ether_type, sizeof(ether_type));

  cfg.set_egress_qav_idle_slope_bps(0, bandwidth_bps);

  int done = 0;
  if(bandwidth_bps == 0 || packet_length == 0){
    done = 1;
  }
  while(!done)
  {

    ethernet_send_hp_packet(c_tx_hp, (char *)data, packet_length, ETHERNET_ALL_INTERFACES);
    select
    {
      case c_lp_done :> done:
        break;
      default:
        break; 
    }
  }

  c_xscope_control :> int _;
  debug_printf("Got shutdown from host HP\n");
  c_xscope_control <: 1; // Indicate shutdown
}