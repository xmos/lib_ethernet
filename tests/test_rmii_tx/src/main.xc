// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include <stdio.h>
#include <stdlib.h>
#include "ethernet.h"

port p_test_ctrl = on tile[0]: XS1_PORT_1M;

port p_eth_clk = XS1_PORT_1J;
// rmii_data_port_t p_eth_rxd = {{XS1_PORT_1A, XS1_PORT_1B}};
rmii_data_port_t p_eth_rxd = {{XS1_PORT_4A, USE_LOWER_2B}};


#if TX_WIDTH == 4
#if ((TX_USE_LOWER_2B == 1) && (TX_USE_UPPER_2B == 1))
  #error Both TX_USE_LOWER_2B and TX_USE_UPPER_2B set
#endif

#if ((TX_USE_LOWER_2B == 0) && (TX_USE_UPPER_2B == 0))
  #error Both TX_USE_LOWER_2B and TX_USE_UPPER_2B are 0 when TX_WIDTH is 4
#endif

#if TX_USE_LOWER_2B
  rmii_data_port_t p_eth_txd = {{XS1_PORT_4B, USE_LOWER_2B}};
#elif TX_USE_UPPER_2B
  rmii_data_port_t p_eth_txd = {{XS1_PORT_4B, USE_UPPER_2B}};
#endif

#elif TX_WIDTH == 1
rmii_data_port_t p_eth_txd = {{XS1_PORT_1C, XS1_PORT_1D}};
#else
#error invalid TX_WIDTH
#endif

port p_eth_rxdv = XS1_PORT_1K;
port p_eth_txen = XS1_PORT_1L;
clock eth_rxclk = XS1_CLKBLK_1;
clock eth_txclk = XS1_CLKBLK_2;



#define PACKET_BYTES 63
#define PACKET_WORDS ((PACKET_BYTES+3)/4)

#define VLAN_TAGGED 1

#define MII_CREDIT_FRACTIONAL_BITS 16

struct test_packet { int len; int step; int tagged; }
test_packets[] =
{
    { 64, 1, 0 },
    { 65, 5, 1 },
    { 66, 1, 0 },
    { 67, 5, 1 },
};

void test_tx(client ethernet_tx_if tx_lp, streaming chanend ? c_tx_hp)
{
  p_test_ctrl <: 0;
  for (int i = 0; i < sizeof(test_packets)/sizeof(test_packets[0]); i++)
  {
    char data[ETHERNET_MAX_PACKET_SIZE];

    // src/dst MAC addresses
    size_t j = 0;
    for (; j < 12; j++)
      data[j] = j;

    int len = test_packets[i].len - 14;

    if (test_packets[i].tagged) {
      data[j++] = 0x81;
      data[j++] = 0x00;
      data[j++] = 0x00;
      data[j++] = 0x00;

      // There will be 4 less data bytes with the VLAN/Priority tag
      len -= 4;
    }

    data[j++] = len >> 8;
    data[j++] = len & 0xff;

    int x = 0;
    for (; j < test_packets[i].len; j++) {
      x += test_packets[i].step;
      data[j] = x;
    }

    if (isnull(c_tx_hp)) {
      tx_lp.send_packet(data, test_packets[i].len, ETHERNET_ALL_INTERFACES);
    }
    else {
      ethernet_send_hp_packet(c_tx_hp, data, test_packets[i].len, ETHERNET_ALL_INTERFACES);
    }
  }

  // Give time for the packet to start to be sent in the case of the RT MAC
  timer t;
  int time;
  t :> time;
  t when timerafter(time + 5000) :> time;

  // Signal that all packets have been sent
  p_test_ctrl <: 1;
}

int main()
{
    ethernet_cfg_if i_cfg[1];
    ethernet_rx_if i_rx_lp[1];
    ethernet_tx_if i_tx_lp[1];
#if ETHERNET_SUPPORT_HP_QUEUES
    streaming chan c_rx_hp;
    streaming chan c_tx_hp;
#else
    #define c_rx_hp null
    #define c_tx_hp null
#endif


    par {
        unsafe{rmii_ethernet_rt_mac(i_cfg, 1,
                                    i_rx_lp, 1,
                                    i_tx_lp, 1,
                                    c_rx_hp, c_tx_hp,
                                    p_eth_clk,
                                    &p_eth_rxd, p_eth_rxdv,
                                    p_eth_txen, &p_eth_txd,
                                    eth_rxclk, eth_txclk,
                                    4000, 4000, ETHERNET_DISABLE_SHAPER);}
#if ETHERNET_SUPPORT_HP_QUEUES
      test_tx(i_tx_lp[0], c_tx_hp);
#else
      test_tx(i_tx_lp[0], null);
#endif
    }

    return 0;
}
