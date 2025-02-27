// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include <stdlib.h>
#include "otp_board_info.h"
#include "ethernet.h"
#include "test_rx.h"
#include "xscope_control.h"
#include "smi.h"
#include "xk_eth_xu316_dual_100m/board.h"
#include <xscope.h>
#include "debug_print.h"
#include "rmii_port_defines.h" // RMII port definitions

#if MULTIPLE_QUEUES
#define NUM_RX_LP_IF 2
#define NUM_TX_LP_IF 2
#define NUM_RX_HP_IF 1
#else
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1
#define NUM_RX_HP_IF 0
#endif

#define NUM_CFG_CLIENTS   NUM_RX_HP_IF + NUM_RX_LP_IF + 1 /*phy_driver*/
#define ETH_RX_BUFFER_SIZE_WORDS 4000

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  smi_if i_smi;
  chan c_xscope;
  chan c_clients[NUM_CFG_CLIENTS - 1]; // Exclude phy_driver
#if NUM_RX_HP_IF
  streaming chan c_rx_hp;
#else
  #define c_rx_hp null
#endif


  par {
    xscope_host_data(c_xscope);

    on tile[0]:
    {
      par {
        while(1) // To allow re-starting the mac+client threads after a restart
        {
          par {
            rmii_ethernet_rt_mac( i_cfg, NUM_CFG_CLIENTS,
                                        i_rx_lp, NUM_RX_LP_IF,
                                        i_tx_lp, NUM_TX_LP_IF,
                                        c_rx_hp, null,
                                        p_phy_clk,
                                        p_phy_rxd_0,
                                        p_phy_rxd_1,
                                        RX_PINS,
                                        p_phy_rxdv,
                                        p_phy_txen,
                                        p_phy_txd_0,
                                        p_phy_txd_1,
                                        TX_PINS,
                                        phy_rxclk,
                                        phy_txclk,
                                        get_port_timings(0),
                                        ETH_RX_BUFFER_SIZE_WORDS, ETH_RX_BUFFER_SIZE_WORDS,
                                        ETHERNET_DISABLE_SHAPER);
            test_rx_lp(i_cfg[1], i_rx_lp[0], i_tx_lp[0], 0, c_clients[0]);
          }
        }


        {
          xscope_control(c_xscope, c_clients, NUM_CFG_CLIENTS-1);
          _Exit(0);
        }
      }
    }
    on tile[1]:
    {
      par {
        dual_dp83826e_phy_driver(i_smi, i_cfg[0], null);
        smi(i_smi, p_smi_mdio, p_smi_mdc);
      }
    }


#if MULTIPLE_QUEUES
    // RX threads
    par ( size_t i = 1; i < NUM_RX_LP_IF; i ++)
    {
      on tile[0]: test_rx_lp(i_cfg[1+i], i_rx_lp[i], i_tx_lp[i], i, c_clients[i]);
    }
    on tile[0]: test_rx_hp(i_cfg[1+NUM_RX_LP_IF], c_rx_hp, NUM_RX_LP_IF, c_clients[NUM_RX_LP_IF]); // HP is the last client
#endif
  }
  return 0;
}

