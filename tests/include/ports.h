#ifndef __ports_h__
#define __ports_h__

#if RGMII
port p_eth_rxclk            = on tile[1]: XS1_PORT_1O;
port p_eth_rxer             = on tile[1]: XS1_PORT_1A;
port p_eth_rxd_1000         = on tile[1]: XS1_PORT_8A;
port p_eth_rxd_10_100       = on tile[1]: XS1_PORT_4A;
port p_eth_rxd_interframe   = on tile[1]: XS1_PORT_4E;
port p_eth_rxdv             = on tile[1]: XS1_PORT_1B;
port p_eth_rxdv_interframe  = on tile[1]: XS1_PORT_1K;
port p_eth_txclk_in         = on tile[1]: XS1_PORT_1P;
port p_eth_txclk_out        = on tile[1]: XS1_PORT_1G;
port p_eth_txer             = on tile[1]: XS1_PORT_1E;
port p_eth_txen             = on tile[1]: XS1_PORT_1F;
port p_eth_txd              = on tile[1]: XS1_PORT_8B;

clock eth_rxclk             = on tile[1]: XS1_CLKBLK_1;
clock eth_rxclk_interframe  = on tile[1]: XS1_CLKBLK_2;
clock eth_txclk             = on tile[1]: XS1_CLKBLK_3;
clock eth_txclk_out         = on tile[1]: XS1_CLKBLK_4;
#else
port p_eth_rxclk  = on tile[0]: XS1_PORT_1J;
port p_eth_rxd    = on tile[0]: XS1_PORT_4E;
port p_eth_txd    = on tile[0]: XS1_PORT_4F;
port p_eth_rxdv   = on tile[0]: XS1_PORT_1K;
port p_eth_txen   = on tile[0]: XS1_PORT_1L;
port p_eth_txclk  = on tile[0]: XS1_PORT_1I;
port p_eth_int    = on tile[0]: XS1_PORT_1O;
port p_eth_rxerr  = on tile[0]: XS1_PORT_1P;
port p_eth_dummy  = on tile[0]: XS1_PORT_8C;

clock eth_rxclk   = on tile[0]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[0]: XS1_CLKBLK_2;
#endif

port p_smi_mdio   = on tile[0]: XS1_PORT_1M;
port p_smi_mdc    = on tile[0]: XS1_PORT_1N;

#endif // __ports_h__
