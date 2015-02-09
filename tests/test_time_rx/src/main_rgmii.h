// Copyright (c) 2015, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#define NUM_CFG_IF 1
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  streaming chan c_rx_hp;
  streaming chan c_tx_hp;
  control_if i_ctrl[NUM_CFG_IF];

  par {
    on tile[1]: rgmii_ethernet_mac(i_cfg, NUM_CFG_IF,
                                   i_rx_lp, NUM_RX_LP_IF,
                                   i_tx_lp, NUM_TX_LP_IF,
                                   c_rx_hp, c_tx_hp,
                                   p_eth_rxclk, p_eth_rxer, p_eth_rxd_1000, p_eth_rxd_10_100,
                                   p_eth_rxd_interframe, p_eth_rxdv, p_eth_rxdv_interframe,
                                   p_eth_txclk_in, p_eth_txclk_out, p_eth_txer, p_eth_txen,
                                   p_eth_txd, eth_rxclk, eth_rxclk_interframe, eth_txclk,
                                   eth_txclk_out, ETHERNET_DISABLE_SHAPER);

    #if ETHERNET_SUPPORT_HP_QUEUES
    on tile[0]: test_rx(i_cfg[0], c_rx_hp, i_ctrl[0]);
    #else
    on tile[0]: test_rx(i_cfg[0], i_rx_lp[0], i_ctrl[0]);
    #endif

    on tile[0]: control(p_ctrl, i_ctrl, NUM_CFG_IF, NUM_CFG_IF);
  }
  return 0;
}
