// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include "xk_eth_xu316_dual_100m/board.h"
#include "ethernet.h"
#include "icmp.h"
#include "smi.h"
#include "debug_print.h"

#define NUM_PHY_BOARDS_FITTED   2 // 1 if PHY0 only fitted, 2 if both fitted

// Shared
port p_smi_mdio = MDIO;
port p_smi_mdc = MDC;
#define MDC_BIT     2
#define MDIO_BIT    3
port p_smi_mdc_mdio = MDC_MDIO_4BIT;

// PHY 0 - Clock master
port p_phy0_rxd_0 = PHY_0_RXD_4BIT;
port p_phy0_txd_0 = PHY_0_TXD_4BIT;
port p_phy0_rxdv = PHY_0_RXDV;
port p_phy0_txen = PHY_0_TX_EN;
clock phy0_rxclk = on tile[0]: XS1_CLKBLK_1;
clock phy0_txclk = on tile[0]: XS1_CLKBLK_2;
port p_phy0_clk = PHY_0_CLK_50M;

// PHY 1 - Clock slave
port p_phy1_rxd_0 = PHY_1_RXD_0;
port p_phy1_rxd_1 = PHY_1_RXD_1;
#if PHY1_USE_8B
    port p_phy1_txd_0 = PHY_1_TXD_8BIT;
    in port p_unused_0 = PHY_1_TXD_0; // set to Hi-Z
    in port p_unused_1 = PHY_1_TXD_1;
    #define TX8_BIT_0 6
    #define TX8_BIT_1 7
    #define TX_PINS ((TX8_BIT_0 << 16) | (TX8_BIT_1))
    #define p_phy1_txd_1 null
#else
    port p_phy1_txd_0 = PHY_1_TXD_0;
    port p_phy1_txd_1 = PHY_1_TXD_1;
    in port p_unused = PHY_1_TXD_8BIT; // set to Hi-Z
    #define TX_PINS 0
#endif
port p_phy1_rxdv = PHY_1_RXDV;
port p_phy1_txen = PHY_1_TX_EN;
clock phy1_rxclk = on tile[0]: XS1_CLKBLK_3;
clock phy1_txclk = on tile[0]: XS1_CLKBLK_4;
port p_phy1_clk = PHY_1_CLK_50M;


static unsigned char ip_address[4] = {192, 168, 2, 178};
static unsigned char mac_address_phy0[MACADDR_NUM_BYTES] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06};
static unsigned char mac_address_phy1[MACADDR_NUM_BYTES] = {0x11, 0x12, 0x13, 0x14, 0x15, 0x16};

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
#if PHY0
    ethernet_cfg_if i_cfg_0[NUM_CFG_CLIENTS];
    #define PHY0_CFG_IF i_cfg_0[CFG_TO_PHY_DRIVER]
#else
    #define PHY0_CFG_IF null
#endif
#if PHY1
    ethernet_cfg_if i_cfg_1[NUM_CFG_CLIENTS];
    #define PHY1_CFG_IF i_cfg_1[CFG_TO_PHY_DRIVER]
#else 
    #define PHY1_CFG_IF null
#endif
    ethernet_rx_if i_rx[2][NUM_ETH_CLIENTS];
    ethernet_tx_if i_tx[2][NUM_ETH_CLIENTS];
    smi_if i_smi;

    par {
        on tile[0]: unsafe{
            // This will be used for cases where we want the same input clock for both PHYs
            unsafe port p_eth_clk;
            if(NUM_PHY_BOARDS_FITTED == 2){
                p_eth_clk = p_phy1_clk;
            } else {
                p_eth_clk = p_phy0_clk;
            }
            par{
#if PHY0
                {// To ensure PHY pin boot straps are read correctly at exit from reset
                    put_mac_ports_in_hiz(p_phy0_rxd_0, null, p_phy0_txd_0, null, p_phy0_rxdv, p_phy0_txen);
                    delay_milliseconds(5); // Wait until PHY has come out of reset
                    debug_printf("Starting RMII RT MAC on PHY 0\n");
                    rmii_ethernet_rt_mac( i_cfg_0, NUM_CFG_CLIENTS,
                                          i_rx[0], NUM_ETH_CLIENTS,
                                          i_tx[0], NUM_ETH_CLIENTS,
                                          null, null,
                                          (port)p_eth_clk, //p_phy0_clk
                                          p_phy0_rxd_0,
                                          null,
                                          USE_UPPER_2B,
                                          p_phy0_rxdv,
                                          p_phy0_txen,
                                          p_phy0_txd_0,
                                          null,
                                          USE_UPPER_2B,
                                          phy0_rxclk,
                                          phy0_txclk,
                                          4000, 4000,
                                          ETHERNET_DISABLE_SHAPER);
                    (void*)mac_address_phy1; // Remove unused var warning
                }
#endif
#if PHY1
                {
                    // If Tx pins for 8b and 1b commoned, then ensure unused ports are Hi-Z
#if PHY1_USE_8B
                    p_unused_0 :> void;
                    p_unused_1 :> void;
#else
                    p_unused :> void;
#endif
                    // To ensure PHY pin boot straps are read correctly at exit from reset
                    put_mac_ports_in_hiz(p_phy1_rxd_0, p_phy1_rxd_1, p_phy1_txd_0, p_phy1_txd_1, p_phy1_rxdv, p_phy1_txen);
                    delay_milliseconds(5); // Wait until PHY has come out of reset
                    debug_printf("Starting RMII RT MAC on PHY 1\n");
                    rmii_ethernet_rt_mac( i_cfg_1, NUM_CFG_CLIENTS,
                                          i_rx[1], NUM_ETH_CLIENTS,
                                          i_tx[1], NUM_ETH_CLIENTS,
                                          null, null,
                                          (port)p_eth_clk, //p_phy1_clk,
                                          p_phy1_rxd_0,
                                          p_phy1_rxd_1,
                                          0,
                                          p_phy1_rxdv,
                                          p_phy1_txen,
                                          p_phy1_txd_0,
                                          p_phy1_txd_1,
                                          TX_PINS,
                                          phy1_rxclk,
                                          phy1_txclk,
                                          4000, 4000,
                                          ETHERNET_DISABLE_SHAPER);
                    (void*)mac_address_phy0; // Remove unused var warning
                }
#endif
            } // par
        } // on unsafe tile[0]

#if PHY0
        on tile[1]: icmp_server(i_cfg_0[CFG_TO_ICMP],
                                i_rx[0][ETH_TO_ICMP], i_tx[0][ETH_TO_ICMP],
                                ip_address, mac_address_phy0);
#endif
#if PHY1
        on tile[1]: icmp_server(i_cfg_1[CFG_TO_ICMP],
                                i_rx[1][ETH_TO_ICMP], i_tx[1][ETH_TO_ICMP],
                                ip_address, mac_address_phy1);
#endif

        on tile[1]: dual_dp83826e_phy_driver(i_smi, PHY0_CFG_IF, PHY1_CFG_IF);

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
    }
    return 0;
}
