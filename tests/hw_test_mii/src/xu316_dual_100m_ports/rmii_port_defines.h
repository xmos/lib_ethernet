// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __RMII_PORT_DEFINES_H__
#define __RMII_PORT_DEFINES_H__

#include <xs1.h>

port p_smi_mdio = MDIO;
port p_smi_mdc = MDC;

#if USE_PHY0 && USE_PHY1
#error "Error: PHY0 and PHY1 both enabled. Compile with either -DUSE_PHY0=1 or -DUS_PHY1=1"
#endif

#if USE_PHY0
  port p_phy_rxd_0 = PHY_0_RXD_4BIT;
  #define p_phy_rxd_1 null
  port p_phy_txd_0 = PHY_0_TXD_4BIT;
  #define p_phy_txd_1 null
  port p_phy_rxdv = PHY_0_RXDV;
  port p_phy_txen = PHY_0_TX_EN;
  clock phy_rxclk = on tile[0]: XS1_CLKBLK_1;
  clock phy_txclk = on tile[0]: XS1_CLKBLK_2;
  port p_phy_clk = PHY_1_CLK_50M;

  #define TX_PINS USE_UPPER_2B
  #define RX_PINS USE_UPPER_2B

#else

  port p_phy_rxd_0 = PHY_1_RXD_0;
  port p_phy_rxd_1 = PHY_1_RXD_1;

  port p_phy_txd_0 = PHY_1_TXD_0;
  port p_phy_txd_1 = PHY_1_TXD_1;

  port p_phy_rxdv = PHY_1_RXDV;
  port p_phy_txen = PHY_1_TX_EN;
  clock phy_rxclk = on tile[0]: XS1_CLKBLK_1;
  clock phy_txclk = on tile[0]: XS1_CLKBLK_2;
  port p_phy_clk = PHY_1_CLK_50M;

  #define TX_PINS 0
  #define RX_PINS 0

#endif

#endif
