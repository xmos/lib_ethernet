// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include "otp_board_info.h"
#include "ethernet.h"
#include "icmp.h"
#include "smi.h"
#include "xk_eth_xu316_dual_100m/board.h"
#include "debug_print.h"

// Shared
port p_eth_clk = CLK_50M;
port p_smi_mdio   = MDIO;
port p_smi_mdc    = MDC;
#define MDC_BIT  2
#define MDIO_BIT 3
port p_smi_mdc_mdio = MDC_MDIO_4B;

// PHY 1
rmii_data_port_t p_eth_rxd_1 = {{PHY_1_RXD_4B, USE_UPPER_2B}};
rmii_data_port_t p_eth_txd_1 = {{PHY_1_TXD_4B, USE_LOWER_2B}};
port p_eth_rxdv_1 = PHY_1_RXDV;
port p_eth_txen_1 = PHY_1_TX_EN;
clock eth_rxclk_1 = on tile[0]: XS1_CLKBLK_1;
clock eth_txclk_1 = on tile[0]: XS1_CLKBLK_2;

// PHY 2
rmii_data_1b_t p_eth_rxd_2 = {PHY_2_RXD_1B_0, PHY_2_RXD_1B_1};
#if PHY2_USE_8B
#define TX8_BIT_0 7
#define TX8_BIT_1 8
rmii_data_port_t p_eth_txd_2 = {{PHY_2_TXD_8B, 0x00070008}};
#else
rmii_data_1b_t p_eth_txd_2 = {PHY_2_TXD_1B_0, PHY_2_TXD_1B_1};
#endif
port p_eth_rxdv_2 = PHY_2_RXDV;
port p_eth_txen_2 = PHY_2_TX_EN;
clock eth_rxclk_2 = on tile[0]: XS1_CLKBLK_3;
clock eth_txclk_2 = on tile[0]: XS1_CLKBLK_4;



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


const int phy_address_1 = 0x05;
const int phy_address_2 = 0x07;

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_rx_if i_rx[NUM_ETH_CLIENTS];
  ethernet_tx_if i_tx[NUM_ETH_CLIENTS];
  smi_if i_smi;

  par {
#if PHY1
    on tile[0]: unsafe{rmii_ethernet_rt_mac(i_cfg, NUM_CFG_CLIENTS,
                                          i_rx, NUM_ETH_CLIENTS,
                                          i_tx, NUM_ETH_CLIENTS,
                                          null, null,
                                          p_eth_clk,
                                          &p_eth_rxd_1, p_eth_rxdv_1,
                                          p_eth_txen_1, &p_eth_txd_1,
                                          eth_rxclk_1, eth_txclk_1,
                                          4000, 4000, ETHERNET_DISABLE_SHAPER);}
    on tile[1]: dp83826e_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER], phy_address_1);
#endif
#if PHY2
    on tile[0]: unsafe{rmii_ethernet_rt_mac(i_cfg, NUM_CFG_CLIENTS,
                                          i_rx, NUM_ETH_CLIENTS,
                                          i_tx, NUM_ETH_CLIENTS,
                                          null, null,
                                          p_eth_clk,
                                          &p_eth_rxd_2, p_eth_rxdv_2,
                                          p_eth_txen_2, &p_eth_txd_2,
                                          eth_rxclk_2, eth_txclk_2,
                                          4000, 4000, ETHERNET_DISABLE_SHAPER);}
    on tile[1]: dp83826e_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER], phy_address_2);
#endif

#if SINGLE_SMI
    on tile[1]: smi_singleport(i_smi, p_smi_mdc_mdio, MDIO_BIT, MDC_BIT);
#else
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);
#endif
    on tile[0]: icmp_server(i_cfg[CFG_TO_ICMP],
                            i_rx[ETH_TO_ICMP], i_tx[ETH_TO_ICMP],
                            ip_address, otp_ports);
  }
  return 0;
}
