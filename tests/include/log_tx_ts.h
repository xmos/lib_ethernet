// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __LOG_TX_TS_H__
#define __LOG_TX_TS_H__

#include <stdlib.h>

#ifdef __XC__
extern "C" {
#endif

#define TOTAL_NUM_TS_ENTRIES (50000)

typedef struct mii_tx_ts_fifo_t {
  unsigned rd_index;
  unsigned wr_index;
  unsigned num_entries;
  unsigned *fifo;
} mii_tx_ts_fifo_t;

void tx_timestamp_probe();
void increment_tx_ts_queue_write_index();

#ifdef __XC__
} // extern "C"
#endif

#endif
