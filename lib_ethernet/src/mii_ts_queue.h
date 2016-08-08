// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#ifndef __mii_ts_queue_h__
#define __mii_ts_queue_h__
#include "mii_buffering.h"

#ifdef __XC__
extern "C" {
#endif

typedef struct mii_ts_queue_entry_t {
  unsigned timestamp_id;
  unsigned timestamp;
} mii_ts_queue_entry_t;

typedef struct mii_ts_queue_info_t {
  unsigned rd_index;
  unsigned wr_index;
  unsigned num_entries;
  mii_ts_queue_entry_t *fifo;
  swlock_t lock;
} mii_ts_queue_info_t;

typedef mii_ts_queue_info_t *mii_ts_queue_t;

mii_ts_queue_t mii_ts_queue_init(mii_ts_queue_info_t *q, mii_ts_queue_entry_t *buf, int n);

void mii_ts_queue_add_entry(mii_ts_queue_t q, unsigned id, unsigned timestamp);

/** Get an entry.
 *
 *  \returns  1 if there was an entry available, 0 otherwise.
 */
int mii_ts_queue_get_entry(mii_ts_queue_t q, unsigned *id, unsigned *timestamp);

#ifdef __XC__
} // extern "C"
#endif

#endif // __mii_ts_queue_h__
