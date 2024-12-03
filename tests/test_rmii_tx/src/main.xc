// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include <stdio.h>
#include <stdlib.h>
#include "ethernet.h"

port p_test_ctrl = on tile[0]: XS1_PORT_1C;

port p_eth_clk = XS1_PORT_1J;
// rmii_data_port_t p_eth_rxd = {{XS1_PORT_1A, XS1_PORT_1B}};
rmii_data_port_t p_eth_rxd = {{XS1_PORT_4A, USE_LOWER_2B}};

// rmii_data_port_t p_eth_txd = {{XS1_PORT_1C, XS1_PORT_1D}};
rmii_data_port_t p_eth_txd = {{XS1_PORT_4B, USE_LOWER_2B}};

port p_eth_rxdv = XS1_PORT_1K;
port p_eth_txen = XS1_PORT_1L;
clock eth_rxclk = XS1_CLKBLK_1;
clock eth_txclk = XS1_CLKBLK_2;



#define PACKET_BYTES 80
#define PACKET_WORDS ((PACKET_BYTES+3)/4)

#define VLAN_TAGGED 1

#define MII_CREDIT_FRACTIONAL_BITS 16


void test_tx(client ethernet_tx_if tx_lp, streaming chanend ? c_tx_hp)
{
    p_test_ctrl <: 0; // Signal test start

    unsigned data[PACKET_WORDS];
    for (size_t i = 0; i < PACKET_WORDS; i++)
    {
        data[i] = i;
    }

    // src/dst MAC addresses
    size_t j = 0;
    for (; j < 12; j++)
    {
        ((char*)data)[j] = j;
    }

    if (VLAN_TAGGED)
    {
        ((char*)data)[j++] = 0x81;
        ((char*)data)[j++] = 0x00;
        ((char*)data)[j++] = 0x00;
        ((char*)data)[j++] = 0x00;
    }

    const int length = PACKET_BYTES;
    const int header_bytes = VLAN_TAGGED ? 18 : 14;
    ((char*)data)[j++] = (length - header_bytes) >> 8;
    ((char*)data)[j++] = (length - header_bytes) & 0xff;

    for(;j<PACKET_BYTES; j++)
    {
        ((char*)data)[j] = j;
    }

    timer t;
    int time;
    t :> time;
    t when timerafter(time + 3000) :> time; // Delay sending to allow Rx to be setup
    if(isnull(c_tx_hp))
    {
        tx_lp.send_packet((char *)data, length, ETHERNET_ALL_INTERFACES);
    }
    else
    {
        ethernet_send_hp_packet(c_tx_hp, (char*)data, length, ETHERNET_ALL_INTERFACES);
    }
    // Give time for the packet to start to be sent in the case of the RT MAC
    t :> time;
    t when timerafter(time + 5000) :> time;

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
