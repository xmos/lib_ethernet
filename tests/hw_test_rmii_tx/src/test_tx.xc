// Copyright 2013-2025 XMOS LIMITED.
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
#include "xscope_cmd_handler.h"

#define MAX_PACKET_BYTES (6 + 6 + 2 + 1500)

static void wait_us(int microseconds)
{
    timer t;
    unsigned time;

    t :> time;
    t when timerafter(time + (microseconds * 100)) :> void;
}

void test_tx_lp(client ethernet_cfg_if cfg,
                 client ethernet_rx_if rx,
                 client ethernet_tx_if tx,
                 unsigned client_num,
                 chanend c_xscope_control,
                 chanend c_tx_synch
                 )
{
  unsigned seq_id = 0;

  // Initialise client_state
  client_state_t client_state;
  memset(&client_state, 0, sizeof(client_state));
  client_state.tx_packet_len = 1500;
  for(int i=0; i<MACADDR_NUM_BYTES; i++)
  {
    client_state.target_mac_addr[i] = 0xff;
    client_state.source_mac_addr[i] = i+client_num;
  }

  // Initialise client cfg
  client_cfg_t client_cfg;
  client_cfg.client_num = client_num;
  client_cfg.is_hp = 0;

  // Ethernet packet setup
  unsigned char data[MAX_PACKET_BYTES] = {0};
  uint16_t ether_type = 0x2222;
  memcpy(&data[0], client_state.target_mac_addr, sizeof(client_state.target_mac_addr));
  memcpy(&data[6], client_state.source_mac_addr, sizeof(client_state.source_mac_addr));
  memcpy(&data[12], &ether_type, sizeof(ether_type));

  // If client index 0, wait for link up and send a packet cleaner packet
  if(client_cfg.client_num == 0)
  {
    // The first client needs to ensure link is up when returning ready status
    unsigned link_state, link_speed;
    cfg.get_link_state(0, link_state, link_speed);
    while(link_state != ETHERNET_LINK_UP)
    {
      wait_us(1000); // Check every 1ms
      cfg.get_link_state(0, link_state, link_speed);
    }
    debug_printf("Ethernet link up\n");
  }
  tx.send_packet(data, client_state.tx_packet_len, ETHERNET_ALL_INTERFACES);


  while(!client_state.done)
  {
    select{
      case xscope_cmd_handler (c_xscope_control, client_cfg, cfg, client_state );

      default:
        if(client_state.num_tx_packets)
        {
          memcpy(&data[0], client_state.target_mac_addr, sizeof(client_state.target_mac_addr));
          memcpy(&data[6], client_state.source_mac_addr, sizeof(client_state.source_mac_addr));
          memcpy(&data[12], &ether_type, sizeof(ether_type));
          // barrier synch with HP so they start at exactly the same time
#if !SINGLE_CLIENT
          c_tx_synch <: 0;
#endif
          for(int i=0; i<client_state.num_tx_packets; i++)
          {
            memcpy(&data[14], &seq_id, sizeof(i)); // sequence ID
            tx.send_packet(data, client_state.tx_packet_len, ETHERNET_ALL_INTERFACES);
            seq_id++;
          }
          client_state.num_tx_packets = 0;
#if !SINGLE_CLIENT
          c_tx_synch <: 0; // Break HP loop
#endif
        }
        else if(client_state.tx_sweep == 1)
        {
          memcpy(&data[0], client_state.target_mac_addr, sizeof(client_state.target_mac_addr));
          memcpy(&data[6], client_state.source_mac_addr, sizeof(client_state.source_mac_addr));
          memcpy(&data[12], &ether_type, sizeof(ether_type));
          // barrier synch with HP so they start at exactly the same time
#if !SINGLE_CLIENT
          c_tx_synch <: 0;
#endif
          // Sweep through all valid payload sizes sending 100 packets for each
          for(int payload_len=60; payload_len<=1514; payload_len++)
          {
            for(int i=0; i<50; i++) // 50 frames per payload length to keep the test time reasonable
            {
              memcpy(&data[14], &seq_id, sizeof(unsigned)); // sequence ID
              tx.send_packet(data, payload_len, ETHERNET_ALL_INTERFACES);
              seq_id++;
            }
          }
          // for the last payload length, send some more packets so the timestamp logging thread gets to complete a timestamp block
          // for sending over xscope. Timestamps are sent in blocks of 1000, where each entry is made of a timestamp and a packet length.
          // Each packet generates one entry, so send 500 to make a block
          unsigned payload_len = 1514;
          for(int i=0; i<500; i++)
          {
            memcpy(&data[14], &seq_id, sizeof(unsigned)); // sequence ID
            tx.send_packet(data, payload_len, ETHERNET_ALL_INTERFACES);
            seq_id++;
          }
          client_state.tx_sweep = 0;
#if !SINGLE_CLIENT
          c_tx_synch <: 0; // Break HP loop
#endif
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
                 unsigned client_num,
                 chanend c_xscope_control,
                 chanend c_tx_synch)
{
  #define INVALID_BW_AND_LEN (0xffffffff)
  unsigned seq_id = 0;
  unsigned hp_finished = 0;

  // Initialise client_state
  client_state_t client_state;
  memset(&client_state, 0, sizeof(client_state));
  client_state.tx_packet_len = INVALID_BW_AND_LEN;
  client_state.qav_bw_bps = INVALID_BW_AND_LEN;
  for(int i=0; i<MACADDR_NUM_BYTES; i++)
  {
    client_state.target_mac_addr[i] = 0xff;
    client_state.source_mac_addr[i] = i+client_num;
  }

  // Initialise client cfg
  client_cfg_t client_cfg;
  client_cfg.client_num = client_num;
  client_cfg.is_hp = 1;

  // Ethernet packet setup
  unsigned char data[MAX_PACKET_BYTES] = {0};
  uint16_t ether_type = 0x2222;
  memcpy(&data[0], client_state.target_mac_addr, sizeof(client_state.target_mac_addr));
  memcpy(&data[6], client_state.source_mac_addr, sizeof(client_state.source_mac_addr));
  memcpy(&data[12], &ether_type, sizeof(ether_type));

  while(!client_state.done)
  {
    select{
      case xscope_cmd_handler (c_xscope_control, client_cfg, cfg, client_state );

      default:
        if((client_state.qav_bw_bps != INVALID_BW_AND_LEN) && (client_state.tx_packet_len != INVALID_BW_AND_LEN)) // CMD_HOST_SET_DUT_TX_PACKETS cmd has been received
        {
          c_tx_synch :> int _; // synch with LP

          if((client_state.qav_bw_bps != 0) && (client_state.tx_packet_len != 0)) // Send packets
          {
            memcpy(&data[0], client_state.target_mac_addr, sizeof(client_state.target_mac_addr));
            memcpy(&data[6], client_state.source_mac_addr, sizeof(client_state.source_mac_addr));
            memcpy(&data[12], &ether_type, sizeof(ether_type));

            while(!hp_finished)
            {
              memcpy(&data[14], &seq_id, sizeof(seq_id)); // sequence ID
              ethernet_send_hp_packet(c_tx_hp, (char *)data, client_state.tx_packet_len, ETHERNET_ALL_INTERFACES);
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
          client_state.qav_bw_bps = INVALID_BW_AND_LEN;
          client_state.tx_packet_len = INVALID_BW_AND_LEN;
        }
        break;
    } //select
  } // while(!done)
  debug_printf("Got shutdown from host HP\n");
  c_xscope_control <: 1; // Acknowledge shutdown completion
}
