// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __ports_h__
#define __ports_h__

#if RGMII

rgmii_ports_t rgmii_ports = on tile[1]: RGMII_PORTS_INITIALIZER;

#else // !RGMII

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

#endif // RGMII

#endif // __ports_h__
