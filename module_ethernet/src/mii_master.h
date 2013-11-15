#ifndef __mii_master_h__
#define __mii_master_h__
#include "mii_ethernet.h"
#include "mii_buffering.h"
#include "mii_ts_queue.h"

#ifdef __XC__

void mii_master_init(mii_ports_t &mii_ports);

unsafe void mii_master_rx_pins(mii_mempool_t rxmem_hp,
                               mii_mempool_t rxmem_lp,
                               in port p_mii_rxdv,
                               in buffered port:32 p_mii_rxd,
                               streaming chanend c);

unsafe void mii_master_tx_pins(mii_mempool_t hp_queue,
                               mii_mempool_t lp_queue,
                               mii_ts_queue_t ts_queue,
                               out buffered port:32 p_mii_txd,
                               int enable_shaper,
                               volatile int * unsafe idle_slope);

#endif

#endif // __mii_master_h__
