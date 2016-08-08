// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "mii.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#include "ports.h"

port p_ctrl = on tile[0]: XS1_PORT_1C;
#include "control.xc"

#include "helpers.xc"

#if RGMII || RT

#if ETHERNET_SUPPORT_HP_QUEUES

void test_rx(client ethernet_cfg_if cfg,
             streaming chanend c_rx_hp,
             client control_if ctrl)
{
  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;
  cfg.add_macaddr_filter(0, 1, macaddr_filter);

  char seq_id = 0;
  int num_bytes = 0;
  int num_packets = 0;
  int done = 0;
  unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
  while (!done) {
    ethernet_packet_info_t packet_info;

    #pragma ordered
    select {
    case ethernet_receive_hp_packet(c_rx_hp, rxbuf, packet_info):
      num_bytes += packet_info.len;
      num_packets += 1;
      if (rxbuf[18] != seq_id) {
        debug_printf("Packet %d instead of %d\n", rxbuf[18], seq_id);
        _exit(1);
      }

      seq_id += 1;
      break;

    case ctrl.status_changed():
      status_t status;
      ctrl.get_status(status);
      if (status == STATUS_DONE)
        done = 1;
      break;
    }
  }
  debug_printf("Received %d packets, %d bytes\n", num_packets, num_bytes);
  ctrl.set_done();
}

#else // !ETHERNET_SUPPORT_HP_QUEUES

void test_rx(client ethernet_cfg_if cfg,
             client ethernet_rx_if rx,
             client control_if ctrl)
{
  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;

  size_t index = rx.get_index();
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  int num_bytes = 0;
  int num_packets = 0;
  int done = 0;
  while (!done) {
    #pragma ordered
    select {
    case rx.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);
      num_bytes += packet_info.len;
      num_packets += 1;
      break;

    case ctrl.status_changed():
      status_t status;
      ctrl.get_status(status);
      if (status == STATUS_DONE)
        done = 1;
      break;
    }
  }
  debug_printf("Received %d packets, %d bytes\n", num_packets, num_bytes);
  ctrl.set_done();
}

#endif // ETHERNET_SUPPORT_HP_QUEUES

#endif // RGMII || RT

#if RGMII
  #include "main_rgmii.h"
#else
  #if RT
    #include "main_mii_rt.h"
  #else
    #include "main_mii_standard.h"
  #endif
#endif

