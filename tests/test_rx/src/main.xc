// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"
#include "xta_test_pragmas.h"

typedef enum {
  STATUS_ACTIVE,
  STATUS_DONE
} status_t;

typedef interface control_if {
  [[notification]] slave void status_changed();
  [[clears_notification]] void get_status(status_t &status);
} control_if;

port p_smi_mdio   = on tile[0]: XS1_PORT_1M;
port p_smi_mdc    = on tile[0]: XS1_PORT_1N;
port p_eth_rxclk  = on tile[0]: XS1_PORT_1J;
port p_eth_rxd    = on tile[0]: XS1_PORT_4E;
port p_eth_txd    = on tile[0]: XS1_PORT_4F;
port p_eth_rxdv   = on tile[0]: XS1_PORT_1K;
port p_eth_txen   = on tile[0]: XS1_PORT_1L;
port p_eth_txclk  = on tile[0]: XS1_PORT_1I;
port p_eth_int    = on tile[0]: XS1_PORT_1O;
port p_eth_rxerr  = on tile[0]: XS1_PORT_1P;
port p_eth_dummy  = on tile[0]: XS1_PORT_8C;

port p_ctrl       = on tile[0]: XS1_PORT_1A;

clock eth_rxclk   = on tile[0]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[0]: XS1_CLKBLK_2;


void test_rx(client ethernet_if eth, client control_if ctrl)
{
  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.vlan = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;
  eth.add_macaddr_filter(macaddr_filter);

  int done = 0;
  while (!done) {
    select {
    case ctrl.status_changed():
      status_t status;
      ctrl.get_status(status);
      if (status == STATUS_DONE)
	done = 1;
      break;
      
    case eth.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      eth.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);
      debug_printf("Received packet, type=%d, len=%d.\n",
                   packet_info.type, packet_info.len);
      int step;
      int start;
      if (rxbuf[12] == 0x81 && rxbuf[13] == 0x00) {
	// VLAN/Prio tagged
	step = rxbuf[19] - rxbuf[18];
	start = 19;
      } else {
	// Non-tagged
	step = rxbuf[15] - rxbuf[14];
	start = 15;
      }
      debug_printf("Step = %d\n", step);
      for (size_t i = start; i < packet_info.len - 1; i++) {
        if ((uint8_t) (rxbuf[i+1] - rxbuf[i]) != step) {
          debug_printf("ERROR: byte %d is %d more than byte %d (expected %d)\n",
                       i+1, rxbuf[i+1] - rxbuf[i], i, step);

	  // Only print one error per packet
	  break;
        }
      }
      break;
    }
  }
  _exit(0);
}

void control(port p_ctrl, server control_if ctrl)
{
  int tmp;
  status_t current_status = STATUS_ACTIVE;
  
  while (1) {
    select {
    case current_status != STATUS_DONE => p_ctrl when pinseq(1) :> tmp:
        current_status = STATUS_DONE;
        ctrl.status_changed();
        break;
    case ctrl.get_status(status_t &status):
	status = current_status;
	break;
    }
  }
}

#define ETH_RX_BUFFER_SIZE_WORDS 1600

int main()
{
  ethernet_if i_eth[1];
  control_if i_ctrl;

  par {
    #if RT
    on tile[0]: mii_ethernet_rt(i_eth, 1,
                                p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                p_eth_txclk, p_eth_txen, p_eth_txd,
                                eth_rxclk, eth_txclk,
                                2000, 2000, 2000, 2000, 1);
    #else
    on tile[0]: mii_ethernet(i_eth, 1,
                             p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                             p_eth_txclk, p_eth_txen, p_eth_txd,
                             p_eth_dummy,
                             eth_rxclk, eth_txclk,
                             ETH_RX_BUFFER_SIZE_WORDS);
    #endif

    on tile[0]: test_rx(i_eth[0], i_ctrl);
    on tile[0]: control(p_ctrl, i_ctrl);
  }
  return 0;
}
