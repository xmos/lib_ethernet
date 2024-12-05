#ifndef __ports_rmii_h__
#define __ports_rmii_h__

port p_test_ctrl = on tile[0]: XS1_PORT_1M;

port p_eth_clk = XS1_PORT_1J;

#if (!defined RX_WIDTH || (RX_WIDTH != 4 && RX_WIDTH != 1))
  #warning RX_WIDTH not defined. Setting default to RX_WIDTH = 4 and USE_LOWER_2B
  #define RX_WIDTH (4)
  #define RX_USE_LOWER_2B (1)
  #define RX_USE_UPPER_2B (0)
#endif

#if (!defined TX_WIDTH || (TX_WIDTH != 4 && TX_WIDTH != 1))
  #warning TX_WIDTH not defined. Setting default to TX_WIDTH = 4 and USE_LOWER_2B
  #define TX_WIDTH (4)
  #define TX_USE_LOWER_2B (1)
  #define TX_USE_UPPER_2B (0)
#endif

#if RX_WIDTH == 4
#if ((RX_USE_LOWER_2B == 1) && (RX_USE_UPPER_2B == 1))
  #error Both RX_USE_LOWER_2B and RX_USE_UPPER_2B set
#endif

#if ((RX_USE_LOWER_2B == 0) && (RX_USE_UPPER_2B == 0))
  #error Both RX_USE_LOWER_2B and RX_USE_UPPER_2B are 0 when RX_WIDTH is 4
#endif

#if RX_USE_LOWER_2B
rmii_data_port_t p_eth_rxd = {{XS1_PORT_4A, USE_LOWER_2B}};
#elif RX_USE_UPPER_2B
rmii_data_port_t p_eth_rxd = {{XS1_PORT_4A, USE_UPPER_2B}};
#endif

#elif RX_WIDTH == 1
rmii_data_port_t p_eth_rxd = {{XS1_PORT_1A, XS1_PORT_1B}};
#else
#error invalid RX_WIDTH
#endif


#if TX_WIDTH == 4
#if ((TX_USE_LOWER_2B == 1) && (TX_USE_UPPER_2B == 1))
  #error Both TX_USE_LOWER_2B and TX_USE_UPPER_2B set
#endif

#if ((TX_USE_LOWER_2B == 0) && (TX_USE_UPPER_2B == 0))
  #error Both TX_USE_LOWER_2B and TX_USE_UPPER_2B are 0 when TX_WIDTH is 4
#endif

#if TX_USE_LOWER_2B
  rmii_data_port_t p_eth_txd = {{XS1_PORT_4B, USE_LOWER_2B}};
#elif TX_USE_UPPER_2B
  rmii_data_port_t p_eth_txd = {{XS1_PORT_4B, USE_UPPER_2B}};
#endif

#elif TX_WIDTH == 1
rmii_data_port_t p_eth_txd = {{XS1_PORT_1C, XS1_PORT_1D}};
#else
#error invalid TX_WIDTH
#endif

port p_eth_rxdv = XS1_PORT_1K;
port p_eth_txen = XS1_PORT_1L;
clock eth_rxclk = XS1_CLKBLK_1;
clock eth_txclk = XS1_CLKBLK_2;

#endif
