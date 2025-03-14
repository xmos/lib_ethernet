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


port p_smi_mdio = MDIO;
port p_smi_mdc = MDC;

port p_phy_rxd = PHY_0_RXD_4BIT;
port p_phy_txd = PHY_0_TXD_4BIT;
port p_phy_rxdv = PHY_0_RXDV;
port p_phy_txen = PHY_0_TX_EN;
port p_phy_clk = PHY_1_CLK_50M;

clock phy_rxclk = on tile[0]: XS1_CLKBLK_1;
clock phy_txclk = on tile[0]: XS1_CLKBLK_2;


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

#define ETH_RX_BUFFER_SIZE_WORDS 1600

// Set to your desired IP address
static unsigned char ip_address[4] = {192, 168, 1, 178};
// MAC address within the XMOS block of 00:22:97:xx:xx:xx. Please adjust to your desired address.
static unsigned char mac_address_phy[MACADDR_NUM_BYTES] = {0x00, 0x22, 0x97, 0x01, 0x02, 0x03};


int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_rx_if i_rx[NUM_ETH_CLIENTS];
  ethernet_tx_if i_tx[NUM_ETH_CLIENTS];
  smi_if i_smi;

  par {
    on tile[0]: rmii_ethernet_rt_mac( i_cfg, NUM_CFG_CLIENTS,
                                      i_rx, NUM_ETH_CLIENTS,
                                      i_tx, NUM_ETH_CLIENTS,
                                      null, null,
                                      p_phy_clk,
                                      p_phy_rxd,
                                      null,
                                      USE_UPPER_2B,
                                      p_phy_rxdv,
                                      p_phy_txen,
                                      p_phy_txd,
                                      null,
                                      USE_UPPER_2B,
                                      phy_rxclk,
                                      phy_txclk,
                                      get_port_timings(0),
                                      ETH_RX_BUFFER_SIZE_WORDS, ETH_RX_BUFFER_SIZE_WORDS,
                                      ETHERNET_DISABLE_SHAPER);

    on tile[1]: dual_dp83826e_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER], null);
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);
    on tile[0]: icmp_server(i_cfg[CFG_TO_ICMP],
                            i_rx[ETH_TO_ICMP], i_tx[ETH_TO_ICMP],
                            ip_address, mac_address_phy);
  }
  return 0;
}
