// Copyright 2014-2025 XMOS LIMITED.
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
#include "xk_eth_xu316_dual_100m/board.h"
#include "log_tx_ts.h"


port p_smi_mdio = MDIO;
port p_smi_mdc = MDC;

port p_phy_rxd = PHY_0_RXD_4BIT;
port p_phy_txd = PHY_0_TXD_4BIT;
port p_phy_rxdv = PHY_0_RXDV;
port p_phy_txen = PHY_0_TX_EN;
clock phy_rxclk = on tile[0]: XS1_CLKBLK_1;
clock phy_txclk = on tile[0]: XS1_CLKBLK_2;
port p_phy_clk = PHY_1_CLK_50M;

#if SINGLE_CLIENT
  #define NUM_TX_LP_IF 1
  #define NUM_RX_LP_IF 1
#else
  #define NUM_TX_LP_IF 2
  #define NUM_RX_LP_IF 2
#endif
#define NUM_CFG_CLIENTS NUM_RX_LP_IF + 1 /*phy_driver*/
#define ETH_RX_BUFFER_SIZE_WORDS 4000

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  smi_if i_smi;
  chan c_xscope;
  chan c_clients[NUM_CFG_CLIENTS - 1]; // Exclude lan8710a_phy_driver
#if !SINGLE_CLIENT
  streaming chan c_tx_hp;
#else
  #define c_tx_hp null
#endif
  chan c_tx_synch;




  par {
    xscope_host_data(c_xscope);

    on tile[0]: rmii_ethernet_rt_mac( i_cfg, NUM_CFG_CLIENTS,
                                      i_rx_lp, NUM_RX_LP_IF,
                                      i_tx_lp, NUM_TX_LP_IF,
                                      null, c_tx_hp,
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
                                  #if !SINGLE_CLIENT
                                      ETHERNET_ENABLE_SHAPER
                                  #else
                                      ETHERNET_DISABLE_SHAPER
                                  #endif
                                      );
#if PROBE_TX_TIMESTAMPS
    on tile[0]: tx_timestamp_probe();
#endif
    on tile[1]: dual_dp83826e_phy_driver(i_smi, i_cfg[0], null);

    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    // TX threads
    on tile[1]: test_tx_lp(i_cfg[1],  i_rx_lp[0], i_tx_lp[0], 0, c_clients[0], c_tx_synch);
#if !SINGLE_CLIENT
    on tile[1]: test_tx_hp(i_cfg[2],  i_rx_lp[1], c_tx_hp, 1, c_clients[1], c_tx_synch);
#endif
    on tile[1]: {
      xscope_control(c_xscope, c_clients, NUM_CFG_CLIENTS-1);
      _Exit(0);
    }

  }
  return 0;
}
