// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include "xk_eth_xu316_dual_100m/board.h"
#include "otp_board_info.h"
#include "ethernet.h"
#include "icmp.h"
#include "smi.h"
#include "debug_print.h"

// Shared
port p_smi_mdio = MDIO;
port p_smi_mdc = MDC;
#define MDC_BIT     2
#define MDIO_BIT    3
port p_smi_mdc_mdio = MDC_MDIO_4BIT;


#if PHY0
port p_eth_rxd_0 = PHY_0_RXD_4BIT;
#define p_eth_rxd_1 null
#define RX_PINS USE_UPPER_2B
port p_eth_txd_0 = PHY_0_TXD_4BIT;
#define p_eth_txd_1 null
#define TX_PINS USE_UPPER_2B
port p_eth_rxdv = PHY_0_RXDV;
port p_eth_txen = PHY_0_TX_EN;
clock eth_rxclk = on tile[0]: XS1_CLKBLK_1;
clock eth_txclk = on tile[0]: XS1_CLKBLK_2;
port p_eth_clk = PHY_0_CLK_50M;
#define PHY_USED USE_PHY_0
#endif

#if PHY1
port p_eth_rxd_0 = PHY_1_RXD_1BIT_0;
port p_eth_rxd_1 = PHY_1_RXD_1BIT_1;
#define RX_PINS 0
#if PHY1_USE_8B
#define TX8_BIT_0 7
#define TX8_BIT_1 8
#define TX_PINS ((TX8_BIT_0 << 16) | (TX8_BIT_1))
port p_eth_txd_0 = PHY_1_TXD_8BIT;
#define p_eth_txd_1 null
#else
port p_eth_txd_0 = PHY_1_TXD_1BIT_0;
port p_eth_txd_1 = PHY_1_TXD_1BIT_1;
#define TX_PINS 0
#endif
#define PHY_ADDR 0x07
port p_eth_rxdv = PHY_1_RXDV;
port p_eth_txen = PHY_1_TX_EN;
clock eth_rxclk = on tile[0]: XS1_CLKBLK_1;
clock eth_txclk = on tile[0]: XS1_CLKBLK_2;
port p_eth_clk = PHY_1_CLK_50M;
#define PHY_USED USE_PHY_1
#endif


// These ports are for accessing the OTP memory
otp_ports_t otp_ports = on tile[0]: OTP_PORTS_INITIALIZER;

static unsigned char ip_address[4] = {192, 168, 1, 178};

// An enum to manage the array of connections from the ethernet component
// to its clients.
enum eth_clients {
    ETH_TO_ICMP,
    NUM_ETH_CLIENTS
};

enum cfg_clients {
    CFG_TO_ICMP,
    CFG_TO_PHY_DRIVER,
    NUM_CFG_CLIENTS
};

void put_mac_ports_in_hiz(port p_rxd_0, port ?p_rxd_1, port p_txd_0, port ?p_txd_1, port p_rxdv, port p_txen){
    p_rxd_0 :> int _;
    if(!isnull(p_rxd_1)) p_rxd_1 :> int _;
    p_txd_0 :> int _;
    if(!isnull(p_txd_1)) p_txd_1 :> int _;
    p_rxdv :> int _;
    p_txen :> int _;
}

int main()
{
    ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
    ethernet_rx_if i_rx[NUM_ETH_CLIENTS];
    ethernet_tx_if i_tx[NUM_ETH_CLIENTS];
    smi_if i_smi;

    par {
        on tile[0]: {
            // To ensure PHY pin boot straps are read correctly at exit from reset
            put_mac_ports_in_hiz(p_eth_rxd_0, p_eth_rxd_1, p_eth_txd_0, p_eth_txd_1, p_eth_rxdv, p_eth_txen);
            debug_printf("Starting MII RT MAC\n");
            delay_milliseconds(5); // Wait until PHY has come out of reset
            rmii_ethernet_rt_mac( i_cfg, NUM_CFG_CLIENTS,
                              i_rx, NUM_ETH_CLIENTS,
                              i_tx, NUM_ETH_CLIENTS,
                              null, null,
                              p_eth_clk,
                              p_eth_rxd_0,
                              p_eth_rxd_1,
                              RX_PINS,
                              p_eth_rxdv,
                              p_eth_txen,
                              p_eth_txd_0,
                              p_eth_txd_1,
                              TX_PINS,
                              eth_rxclk,
                              eth_txclk,
                              4000, 4000,
                              ETHERNET_DISABLE_SHAPER);
        }
        on tile[1]: dp83826e_phy_driver(i_smi, PHY_USED, i_cfg[CFG_TO_PHY_DRIVER], null);

#if SINGLE_SMI
        on tile[1]: {
            p_smi_mdio :> void; // Make 1b MDIO pin Hi-Z
            p_smi_mdc :> void; // Make 1b MDC pin Hi-Z
            debug_printf("Starting SMI singleport\n");
            smi_singleport(i_smi, p_smi_mdc_mdio, MDIO_BIT, MDC_BIT);
        }
#else
        on tile[1]: {
            p_smi_mdc_mdio :> void; // Make 4b MDIO/MDC pins Hi-Z
            debug_printf("Starting SMI one-bit port\n");
            smi(i_smi, p_smi_mdio, p_smi_mdc);
        }
#endif
        on tile[0]: icmp_server(i_cfg[CFG_TO_ICMP],
                                i_rx[ETH_TO_ICMP], i_tx[ETH_TO_ICMP],
                                ip_address, otp_ports);
    }
    return 0;
}
