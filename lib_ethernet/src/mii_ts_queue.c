// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#include "mii_ts_queue.h"
#include "mii_buffering.h"

mii_ts_queue_t mii_ts_queue_init(mii_ts_queue_info_t *q, mii_ts_queue_entry_t *buf, int n)
{
  q->num_entries = n;
  q->fifo = (mii_ts_queue_entry_t *)buf;

  if (!ETHERNET_USE_HARDWARE_LOCKS) {
    swlock_init((swlock_t *)q->lock);
  }

  q->rd_index = 0;
  q->wr_index = 0;
  return q;
}

void mii_ts_queue_add_entry(mii_ts_queue_t q, unsigned id, unsigned timestamp)
{
  if (ETHERNET_USE_HARDWARE_LOCKS) {
    hwlock_acquire(ethernet_memory_lock);
  }
  else {
    swlock_acquire((swlock_t *) q->lock);
  }

  unsigned wr_index = q->wr_index;
  q->fifo[wr_index].timestamp_id = id;
  q->fifo[wr_index].timestamp = timestamp;
  wr_index = increment_and_wrap_to_zero(wr_index, q->num_entries);
  q->wr_index = wr_index;

  if (ETHERNET_USE_HARDWARE_LOCKS) {
    hwlock_release(ethernet_memory_lock);
  }
  else {
    swlock_release((swlock_t *) q->lock);
  }
  return;
}

int mii_ts_queue_get_entry(mii_ts_queue_t q, unsigned *id, unsigned *timestamp)
{
  if (ETHERNET_USE_HARDWARE_LOCKS) {
    hwlock_acquire(ethernet_memory_lock);
  }
  else {
    swlock_acquire((swlock_t *) q->lock);
  }

  unsigned found = 0;
  unsigned rd_index = q->rd_index;
  if (rd_index != q->wr_index) {
    found = 1;
    *id = q->fifo[rd_index].timestamp_id;
    *timestamp = q->fifo[rd_index].timestamp;
    rd_index = increment_and_wrap_to_zero(rd_index, q->num_entries);
    q->rd_index = rd_index;
  }

  if (ETHERNET_USE_HARDWARE_LOCKS) {
    hwlock_release(ethernet_memory_lock);
  }
  else {
    swlock_release((swlock_t *) q->lock);
  }

  return found;
}
