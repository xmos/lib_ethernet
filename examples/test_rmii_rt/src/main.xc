// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include "ethernet.h"

port p_eth_clk = XS1_PORT_1J;
// rmii_data_port_t p_eth_rxd = {{XS1_PORT_1A, XS1_PORT_1B}};
rmii_data_port_t p_eth_rxd = {{XS1_PORT_4A, USE_LOWER_2B}};

rmii_data_port_t p_eth_txd = {{XS1_PORT_1C, XS1_PORT_1D}};
// rmii_data_port_t p_eth_txd = {{XS1_PORT_4B, USE_LOWER_2B}};

port p_eth_rxdv = XS1_PORT_1K;
port p_eth_txen = XS1_PORT_1L;
clock eth_rxclk = XS1_CLKBLK_1;
clock eth_txclk = XS1_CLKBLK_2;


void application(client ethernet_cfg_if i_cfg,
client ethernet_rx_if i_rx,
client ethernet_tx_if i_tx,
streaming chanend c_rx_hp,
streaming chanend c_tx_hp)
{
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
                ethernet_send_hp_packet(c_tx_hp, rxbuf, packet_info.len, ETHERNET_ALL_INTERFACES);
                break;
        }
    }
}

int main()
{
    ethernet_cfg_if i_cfg[1];
    ethernet_rx_if i_rx_lp[1];
    ethernet_tx_if i_tx_lp[1];
    streaming chan c_rx_hp;
    streaming chan c_tx_hp;
    

    par {
        unsafe{rmii_ethernet_rt_mac(i_cfg, 1,
                                    i_rx_lp, 1,
                                    i_tx_lp, 1,
                                    c_rx_hp, c_tx_hp,
                                    p_eth_clk,
                                    &p_eth_rxd, p_eth_rxdv,
                                    p_eth_txen, &p_eth_txd,
                                    eth_rxclk, eth_txclk,
                                    4000, 4000, ETHERNET_ENABLE_SHAPER);}
    
        application(i_cfg[0], i_rx_lp[0], i_tx_lp[0], c_rx_hp, c_tx_hp);
    }

    return 0;
}