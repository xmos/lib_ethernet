#include "mii_ts_queue.h"
#include "mii_buffering.h"

mii_ts_queue_t mii_ts_queue_init(mii_ts_queue_info_t *q, unsigned *buf, int n)
{
  q->num_entries = n;
  q->fifo = buf;

  if (!ETHERNET_USE_HARDWARE_LOCKS)
    swlock_init((swlock_t *) q->lock);

  q->rdIndex = 0;
  q->wrIndex = 0;
  return q;
}

void mii_ts_queue_add_entry(mii_ts_queue_t q, mii_packet_t *i)
{
  int wrIndex;

  if (ETHERNET_USE_HARDWARE_LOCKS) {
    hwlock_acquire(ethernet_memory_lock);
  } else {
    swlock_acquire((swlock_t *) q->lock);
  }

  wrIndex = q->wrIndex;
  q->fifo[wrIndex] = (unsigned) i;
  wrIndex++;
  wrIndex *= (wrIndex != q->num_entries);
  q->wrIndex = wrIndex;

  if (ETHERNET_USE_HARDWARE_LOCKS) {
    hwlock_release(ethernet_memory_lock);
  }
  else {
    swlock_release((swlock_t *) q->lock);
  }
  return;
}

mii_packet_t *mii_ts_queue_get_entry(mii_ts_queue_t q)
{
  unsigned i=0;
  int rdIndex, wrIndex;

  if (ETHERNET_USE_HARDWARE_LOCKS) {
    hwlock_acquire(ethernet_memory_lock);
  }
  else {
    swlock_acquire((swlock_t *) q->lock);
  }

  rdIndex = q->rdIndex;
  wrIndex = q->wrIndex;

  if (rdIndex == wrIndex)
    i = 0;
  else {
    i = q->fifo[rdIndex];
    rdIndex++;
    rdIndex *= (rdIndex != q->num_entries);
    q->rdIndex = rdIndex;
  }

  if (ETHERNET_USE_HARDWARE_LOCKS) {
    hwlock_release(ethernet_memory_lock);
  }
  else {
    swlock_release((swlock_t *) q->lock);
  }

  return (mii_packet_t *) i;
}
