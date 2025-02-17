// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#define NUM_CFG_IF 1
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  control_if i_ctrl[NUM_CFG_IF];

  #if ETHERNET_SUPPORT_HP_QUEUES
  streaming chan c_rx_hp;
  streaming chan c_tx_hp;
  #else
  #define c_rx_hp null
  #define c_tx_hp null
  #endif

  par {
  #if MII
    on tile[0]: mii_ethernet_rt_mac(i_cfg, NUM_CFG_IF,
                                    i_rx_lp, NUM_RX_LP_IF,
                                    i_tx_lp, NUM_TX_LP_IF,
                                    c_rx_hp, c_tx_hp,
                                    p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                    p_eth_txclk, p_eth_txen, p_eth_txd,
                                    eth_rxclk, eth_txclk,
                                    4000, 4000, ETHERNET_DISABLE_SHAPER);
  #elif RMII
    on tile[0]: rmii_ethernet_rt_mac( i_cfg, NUM_CFG_IF,
                                      i_rx_lp, NUM_RX_LP_IF,
                                      i_tx_lp, NUM_TX_LP_IF,
                                      c_rx_hp, c_tx_hp,
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
                                      port_timing,
                                      4000, 4000,
                                      ETHERNET_DISABLE_SHAPER);
  #endif
    on tile[0]: filler(0x222);
    on tile[0]: filler(0x333);

    #if ETHERNET_SUPPORT_HP_QUEUES
    on tile[0]: test_rx(i_cfg[0], c_rx_hp, i_ctrl[0]);
    #else
    on tile[0]: test_rx(i_cfg[0], i_rx_lp[0], i_ctrl[0]);
    #endif

    on tile[0]: control(p_test_ctrl, i_ctrl, NUM_CFG_IF, NUM_CFG_IF);
  }
  return 0;
}
