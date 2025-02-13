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

void test_tx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 unsigned client_num,
                 chanend c_xscope_control,
                 chanend c_tx_synch
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

  while(!done)
  {
    select{
      case c_xscope_control :> int cmd: // Command received over xscope
        if(cmd == CMD_DEVICE_CONNECT)
        {
            c_xscope_control <: 1; // Indicate ready
        }
        else if(cmd == CMD_SET_DEVICE_MACADDR)
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
          debug_printf("Received CMD_HOST_SET_DUT_TX_PACKETS command. num_packets = %d\n", num_packets);
          c_xscope_control <: 1; // Acknowledge
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
          // barrier synch with HP so they start at exactly the same time
          c_tx_synch <: 0;
          for(int i=0; i<num_packets; i++)
          {
            memcpy(&data[14], &seq_id, sizeof(i)); // sequence ID
            tx.send_packet(data, packet_length, ETHERNET_ALL_INTERFACES);
            seq_id++;
          }
          num_packets = 0;
          c_tx_synch <: 0; // Break HP loop

        }
        break;
    } //select
  }
  debug_printf("Got shutdown from host LP\n");
  c_xscope_control <: 1; // Acknowledge shutdown completion
}


void test_tx_hp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 streaming chanend c_tx_hp,
                 chanend c_xscope_control,
                 chanend c_tx_synch)
{
  #define INVALID_BW_AND_LEN (0xffffffff)
   // data structures needed for packet
  uint8_t tx_source_mac[MACADDR_NUM_BYTES] = {0, 1, 2, 3, 4, 5};
  uint8_t tx_target_mac[MACADDR_NUM_BYTES] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
  unsigned bandwidth_bps = INVALID_BW_AND_LEN, packet_length = INVALID_BW_AND_LEN;
  uint16_t ether_type = 0x2222;
  unsigned seq_id = 0;
  unsigned done = 0;
  unsigned hp_finished = 0;

  char data[MAX_PACKET_BYTES] = {0};
  memcpy(&data[0], tx_target_mac, sizeof(tx_target_mac));
  memcpy(&data[6], tx_source_mac, sizeof(tx_source_mac));
  memcpy(&data[12], &ether_type, sizeof(ether_type));

  while(!done)
  {
    select{
      case c_xscope_control :> int cmd: // Command received over xscope
        if(cmd == CMD_DEVICE_CONNECT)
        {
            c_xscope_control <: 1; // Indicate ready
        }
        else if(cmd == CMD_SET_DEVICE_MACADDR)
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
          c_xscope_control :> bandwidth_bps;
          c_xscope_control :> packet_length;
          debug_printf("Received CMD_HOST_SET_DUT_TX_PACKETS command. bandwidth_bps = %d\n", bandwidth_bps);
          if(bandwidth_bps)
          {
            cfg.set_egress_qav_idle_slope_bps(0, bandwidth_bps);
          }
          c_xscope_control <: 1; // Acknowledge
        }
        else if(cmd == CMD_DEVICE_SHUTDOWN)
        {
          debug_printf("Received CMD_DEVICE_SHUTDOWN command\n");
          done = 1;
        }
        break;
      default:
        if((bandwidth_bps != INVALID_BW_AND_LEN) && (packet_length != INVALID_BW_AND_LEN)) // CMD_HOST_SET_DUT_TX_PACKETS cmd has been received
        {
          c_tx_synch :> int _; // synch with LP

          if((bandwidth_bps != 0) && (packet_length != 0)) // Send packets
          {
            memcpy(&data[0], tx_target_mac, sizeof(tx_target_mac));
            memcpy(&data[6], tx_source_mac, sizeof(tx_source_mac));
            memcpy(&data[12], &ether_type, sizeof(ether_type));

            while(!hp_finished)
            {
              memcpy(&data[14], &seq_id, sizeof(seq_id)); // sequence ID
              ethernet_send_hp_packet(c_tx_hp, (char *)data, packet_length, ETHERNET_ALL_INTERFACES);
              seq_id++;
              select
              {
                // break sending HP when LP done
                case c_tx_synch :> int _:
                  hp_finished = 1;
                  break;
                default:
                  break;
              }
            } // while
            hp_finished = 0;
          }
          else // Do not send packets. Wait to sync with LP
          {
            c_tx_synch :> int _; // receive break
          }
          bandwidth_bps = INVALID_BW_AND_LEN;
          packet_length = INVALID_BW_AND_LEN;
        }
        break;
    } //select
  } // while(!done)
  debug_printf("Got shutdown from host HP\n");
  c_xscope_control <: 1; // Acknowledge shutdown completion
}
