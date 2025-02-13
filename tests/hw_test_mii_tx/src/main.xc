// Copyright 2014-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include <stdlib.h>
#include "otp_board_info.h"
#include "ethernet.h"
#include "test_tx.h"
#include "xscope_control.h"
#include "smi.h"
#include <xscope.h>
#include "lan8710a_phy_driver.h"


port p_eth_rxclk  = PORT_ETH_RXCLK;
port p_eth_rxd    = PORT_ETH_RXD;
port p_eth_txd    = PORT_ETH_TXD;
port p_eth_rxdv   = PORT_ETH_RXDV;
port p_eth_txen   = PORT_ETH_TXEN;
port p_eth_txclk  = PORT_ETH_TXCLK;
port p_eth_rxerr  = PORT_ETH_RXER;
port p_eth_dummy  = on tile[1]: XS1_PORT_8C;

clock eth_rxclk   = on tile[1]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[1]: XS1_CLKBLK_2;

port p_smi_mdio   = PORT_SMI_MDIO;
port p_smi_mdc    = PORT_SMI_MDC;


#define NUM_TX_LP_IF 2
#define NUM_RX_LP_IF 2
#define NUM_CFG_CLIENTS NUM_RX_LP_IF + 1 /*lan8710a_phy_driver*/

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  smi_if i_smi;
  chan c_xscope;
  chan c_clients[NUM_CFG_CLIENTS];
  streaming chan c_tx_hp;
  chan c_tx_synch;




  par {
    xscope_host_data(c_xscope);
    on tile[1]: mii_ethernet_rt_mac(i_cfg, NUM_CFG_CLIENTS,
                                i_rx_lp, NUM_RX_LP_IF,
                                i_tx_lp, NUM_TX_LP_IF,
                                null, c_tx_hp,
                                p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                p_eth_txclk, p_eth_txen, p_eth_txd,
                                eth_rxclk, eth_txclk,
                                4000, 4000, ETHERNET_ENABLE_SHAPER);

    on tile[1]: lan8710a_phy_driver(i_smi, i_cfg[0], c_clients[0]);

    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    // TX threads
    on tile[0]: test_tx_lp(i_cfg[1],  i_rx_lp[0], i_tx_lp[0], 0, c_clients[1], c_tx_synch);
    on tile[0]: test_tx_hp(i_cfg[2],  i_rx_lp[1], c_tx_hp, c_clients[2], c_tx_synch);

    on tile[0]: {
      xscope_control(c_xscope, c_clients, NUM_CFG_CLIENTS);
      _Exit(0);
    }

  }
  return 0;
}
