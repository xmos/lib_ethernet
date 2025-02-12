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
void test_tx_lp_loop(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 unsigned client_num,
                 chanend c_xscope_control
                 )
{
  unsigned done = 0;
  unsigned seq_id = 0;
  uint8_t tx_source_mac[MACADDR_NUM_BYTES] = {0, 1, 2, 3, 4, 5};
  uint8_t tx_target_mac[MACADDR_NUM_BYTES] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
  unsigned num_packets = 0, packet_length = 1500;
  uint16_t ether_type = 0x2222;
  // Ethernet packet setup
  unsigned char data[MAX_PACKET_BYTES] = {0};
  memcpy(&data[0], tx_target_mac, sizeof(tx_target_mac));
  memcpy(&data[6], tx_source_mac, sizeof(tx_source_mac));
  memcpy(&data[12], &ether_type, sizeof(ether_type));

  c_xscope_control <: 1; // Indicate ready

  while(!done)
  {
    select{
      case c_xscope_control :> int cmd: // Command received over xscope
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
          c_xscope_control :> num_packets;
          c_xscope_control :> packet_length;
          c_xscope_control <: 1; // Acknowledge
          debug_printf("Received CMD_HOST_SET_DUT_TX_PACKETS command. num_packets = %d\n", num_packets);
        }
        else if(cmd == CMD_DEVICE_SHUTDOWN)
        {
          debug_printf("Received CMD_DEVICE_SHUTDOWN command\n");
          done = 1;
        }
        break;
      default:
        if(num_packets)
        {
          memcpy(&data[0], tx_target_mac, sizeof(tx_target_mac));
          memcpy(&data[6], tx_source_mac, sizeof(tx_source_mac));
          memcpy(&data[12], &ether_type, sizeof(ether_type));
          for(int i=0; i<num_packets; i++)
          {
            memcpy(&data[14], &seq_id, sizeof(i)); // sequence ID
            tx.send_packet(data, packet_length, ETHERNET_ALL_INTERFACES);
            seq_id++;
          }
          num_packets = 0;
        }
        break;
    } //select
  }
  debug_printf("Got shutdown from host LP\n");
  c_xscope_control <: 1; // Acknowledge shutdown completion
}
