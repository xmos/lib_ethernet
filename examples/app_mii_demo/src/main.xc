// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include "mii.h"

// Here are the port definitions required by ethernet. This port assignment
// is for the L16 sliceKIT with the ethernet slice plugged into the
// CIRCLE slot.
port p_smi_mdio   = on tile[1]: XS1_PORT_1M;
port p_smi_mdc    = on tile[1]: XS1_PORT_1N;
port p_eth_rxclk  = on tile[1]: XS1_PORT_1J;
port p_eth_rxd    = on tile[1]: XS1_PORT_4E;
port p_eth_txd    = on tile[1]: XS1_PORT_4F;
port p_eth_rxdv   = on tile[1]: XS1_PORT_1K;
port p_eth_txen   = on tile[1]: XS1_PORT_1L;
port p_eth_txclk  = on tile[1]: XS1_PORT_1I;
port p_eth_int    = on tile[1]: XS1_PORT_1O;
port p_eth_rxerr  = on tile[1]: XS1_PORT_1P;
port p_eth_dummy  = on tile[1]: XS1_PORT_8C;

clock eth_rxclk   = on tile[1]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[1]: XS1_CLKBLK_2;

void loopback_packets(client interface mii_if mii)
{
  mii_info_t mii_info = mii.init();
  while (1) {
    select {
    case mii_incoming_packet(mii_info):
      int * unsafe data = NULL;
      do {
        int nbytes;
        unsigned timestamp;
        {data, nbytes, timestamp} = mii.get_incoming_packet();
        if (data) {
          mii.send_packet(data, nbytes);
          // Wait fot the packet to send.
          mii_packet_sent(mii_info);
          mii.release_packet(data);
        }
      } while (data != NULL);
      break;
    }
  }
}

int main()
{
  interface mii_if i_mii;
  par {
    on tile[1]: mii(i_mii, p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv, p_eth_txclk,
                    p_eth_txen, p_eth_txd, p_eth_dummy,
                    eth_rxclk, eth_txclk, 1024)
    on tile[1]: loopback_packets(i_mii);
  }
  return 0;
}
