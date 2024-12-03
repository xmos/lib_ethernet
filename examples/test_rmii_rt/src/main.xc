// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include <stdio.h>
#include <stdlib.h>
#include <print.h>
#include "ethernet.h"

port p_eth_clk = XS1_PORT_1J;

#if TX_WIDTH == 4
rmii_data_port_t p_eth_txd = {{XS1_PORT_4B, USE_LOWER_2B}};
#elif TX_WIDTH == 1
rmii_data_port_t p_eth_txd = {{XS1_PORT_1C, XS1_PORT_1D}};
#else
#error invalid TX_WIDTH
#endif

#if RX_WIDTH == 4
rmii_data_port_t p_eth_rxd = {{XS1_PORT_4A, USE_LOWER_2B}};
#elif RX_WIDTH == 1
rmii_data_port_t p_eth_rxd = {{XS1_PORT_1A, XS1_PORT_1B}};
#else
#error invalid RX_WIDTH
#endif

port p_eth_rxdv = XS1_PORT_1K;
port p_eth_txen = XS1_PORT_1L;
clock eth_rxclk = XS1_CLKBLK_1;
clock eth_txclk = XS1_CLKBLK_2;


// Test harness
clock eth_clk_harness = XS1_CLKBLK_3;
port p_eth_clk_harness = XS1_PORT_1I;

#define MAX_PACKET_WORDS (ETHERNET_MAX_PACKET_SIZE / 4)

#define VLAN_TAGGED 1

#define MII_CREDIT_FRACTIONAL_BITS 16

static int calc_idle_slope(int bps)
{
  long long slope = ((long long) bps) << (MII_CREDIT_FRACTIONAL_BITS);
  slope = slope / 100000000; // bits that should be sent per ref timer tick

  return (int) slope;
}

static void printbytes(char *b, int n){
    for(int i=0; i<n;i++){
        printstr(", 0x"); printhex(b[i]);
    }
    printstr("\n");
}

static void printwords(unsigned *b, int n){
    for(int i=0; i<n;i++){
        printstr(", 0x"); printhex(b[i]);
    }
    printstr("\n");
}


void hp_traffic_tx(client ethernet_cfg_if i_cfg, client ethernet_tx_if tx_lp, streaming chanend c_tx_hp)
{
  // Request 5Mbits/sec
  i_cfg.set_egress_qav_idle_slope(0, calc_idle_slope(5 * 1024 * 1024));

  unsigned data[MAX_PACKET_WORDS];
  for (size_t i = 0; i < MAX_PACKET_WORDS; i++) {
    data[i] = i;
  }

  // src/dst MAC addresses
  size_t j = 0;
  for (; j < 12; j++)
    ((char*)data)[j] = j;

  if (VLAN_TAGGED) {
    ((char*)data)[j++] = 0x81;
    ((char*)data)[j++] = 0x00;
    ((char*)data)[j++] = 0x00;
    ((char*)data)[j++] = 0x00;
  }

  const int length = 61;
  const int header_bytes = VLAN_TAGGED ? 18 : 14;
  ((char*)data)[j++] = (length - header_bytes) >> 8;
  ((char*)data)[j++] = (length - header_bytes) & 0xff;

  timer t;
  int time;
  t :> time;
  t when timerafter(time + 1000) :> time; // Delay sending to allow Rx to be setup

  printf("TX pre\n");

  for(int length = 67; length < 68; length++){
      // printbytes((char*)data, length);
      printwords(data, length/4);
      tx_lp.send_packet((char *)data, length, ETHERNET_ALL_INTERFACES);
      printf("LP packet sent: %d bytes\n", length);
      t :> time;
      t when timerafter(time + 8000) :> time;
  }

  t :> time;
  t when timerafter(time + 1000) :> time; 
  exit(0);
}


void rx_app(client ethernet_cfg_if i_cfg,
            client ethernet_rx_if i_rx,
            streaming chanend c_rx_hp)
{
    printf("rx_app\n");

    ethernet_macaddr_filter_t macaddr_filter;
    size_t index = i_rx.get_index();
    for (int i = 0; i < MACADDR_NUM_BYTES; i++) {
        macaddr_filter.addr[i] = i;
    }
    i_cfg.add_macaddr_filter(index, 1, macaddr_filter);

    while (1) {
        uint8_t rxbuf[ETHERNET_MAX_PACKET_SIZE];
        ethernet_packet_info_t packet_info;
        
        select {
            case ethernet_receive_hp_packet(c_rx_hp, rxbuf, packet_info):
                printf("HP packet received: %d bytes\n", packet_info.len);
                // printbytes(rxbuf, packet_info.len);
                break;

            case i_rx.packet_ready():
                unsigned n;
                i_rx.get_packet(packet_info, rxbuf, n);
                printf("LP packet received: %d bytes\n", n);
                // printbytes(rxbuf, packet_info.len);
                break;
        }
    }
}

int main()
{
    ethernet_cfg_if i_cfg[2];
    ethernet_rx_if i_rx_lp[1];
    ethernet_tx_if i_tx_lp[1];
    streaming chan c_rx_hp;
    streaming chan c_tx_hp;
    

    // Setup 50M clock
    unsigned divider = 20; // 100 / 2 = 50;
    configure_clock_ref(eth_clk_harness, divider / 2); 
    set_port_clock(p_eth_clk_harness, eth_clk_harness);
    set_port_mode_clock(p_eth_clk_harness);
    start_clock(eth_clk_harness);

    par {
        unsafe{rmii_ethernet_rt_mac(i_cfg, 2,
                                    i_rx_lp, 1,
                                    i_tx_lp, 1,
                                    c_rx_hp, c_tx_hp,
                                    p_eth_clk,
                                    &p_eth_rxd, p_eth_rxdv,
                                    p_eth_txen, &p_eth_txd,
                                    eth_rxclk, eth_txclk,
                                    4000, 4000, ETHERNET_ENABLE_SHAPER);}
    
        rx_app(i_cfg[0], i_rx_lp[0], c_rx_hp);
        hp_traffic_tx(i_cfg[1], i_tx_lp[0], c_tx_hp);
    }

    return 0;
}