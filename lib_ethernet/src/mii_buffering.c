// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved
#include <string.h>
#include "mii_buffering.h"
#include "debug_print.h"
#include "xassert.h"

/* A compile-time assertion macro that can contain sizeof and other operators */
#define CASSERT(predicate, msg) _impl_CASSERT_LINE(predicate,msg)
#define _impl_CASSERT_LINE(predicate, msg) \
    typedef char assertion_failed_##msg[2*!!(predicate)-1];

/* Ensure that the define required by the assembler stays inline with the structure */
CASSERT(MII_PACKET_HEADER_BYTES == (sizeof(mii_packet_t) - (((MII_PACKET_DATA_BYTES+3)/4) * 4)), \
        header_bytes_defines_does_not_match_structure)

// Need to have a single implemenation of this somewhere
extern unsigned increment_and_wrap_to_zero(unsigned value, unsigned max);
extern unsigned increment_and_wrap_power_of_2(unsigned value, unsigned max);

// There needs to be a block big enough to put the packet header
// There also needs to be an extra word because the address which
// is compared is pre-incremented.
// Need 3 words extra to ensure dest mac address and ethertype does not wrap
#define MIN_USAGE (MII_PACKET_HEADER_BYTES + 4 + 12)

hwlock_t ethernet_memory_lock = 0;

// Allocate enough room to store the mempool and one packet header
static unsigned dummy_buf[(sizeof(mempool_info_t) + MIN_USAGE + 4)/4];

static mii_packet_t *dummy_packet;
static unsigned * dummy_end_ptr;

static void init_dummy_buf()
{
  mempool_info_t *info = (mempool_info_t *) (void *) &dummy_buf[0];
  info->start = (unsigned *) (((char *) dummy_buf) + sizeof(mempool_info_t));
  info->end = (unsigned *) (((char *) dummy_buf) + sizeof(dummy_buf) - 4);
  info->wrptr = info->start;

  /* Record the last safe address to start a packet. Need to use the word
   * count in the operation. */
  info->last_safe_wrptr = info->end - ((MIN_USAGE + 3) / 4);

  *(info->start) = 0;
  *(info->end) = (unsigned) (info->start);
#if !ETHERNET_USE_HARDWARE_LOCKS
  swlock_init(&info->lock);
#endif
  dummy_packet = (mii_packet_t *)info->wrptr;
  dummy_end_ptr = (unsigned *) ((char *) dummy_packet + MII_PACKET_HEADER_BYTES);
}

void mii_init_packet_queue(mii_packet_queue_t queue)
{
  packet_queue_info_t *info = (packet_queue_info_t *)queue;
  info->rd_index = 0;
  info->wr_index = 0;
  memset(info->ptrs, 0, sizeof(info->ptrs));
}

mii_mempool_t mii_init_mempool(unsigned *buf, int size)
{
  if (size < 4)
    return 0;
  if (dummy_buf[0] == 0)
    init_dummy_buf();
  mempool_info_t *info = (mempool_info_t *) buf;
  info->start = (unsigned *) (((char *) buf) + sizeof(mempool_info_t));
  info->end = (unsigned *) (((char *) buf) + size - 4);
  info->wrptr = info->start;

  /* Record the last safe address to start a packet. Need to use the word
   * count in the operation. */
  info->last_safe_wrptr = info->end - ((MIN_USAGE + 3) / 4);

  *(info->start) = 0;
  *(info->end) = (unsigned) (info->start);

  if (!ETHERNET_USE_HARDWARE_LOCKS) {
    swlock_init(&info->lock);
  }

  return ((mii_mempool_t) info);
}

void mii_init_lock()
{
  if (ETHERNET_USE_HARDWARE_LOCKS) {
    if (ethernet_memory_lock == 0) {
      ethernet_memory_lock = hwlock_alloc();
    }
  }
}

int mii_packet_queue_full(mii_packet_queue_t queue)
{
  // The queue is full if the write pointer is pointing
  // to a non-zero entry
  packet_queue_info_t *info = (packet_queue_info_t *)queue;

  if (info->ptrs[info->wr_index])
    return 1;
  else
    return 0;
}

unsigned *mii_get_wrap_ptr(mii_mempool_t mempool)
{
  mempool_info_t *info = (mempool_info_t *) mempool;
  return (unsigned *) (info->end);
}

mii_packet_t *mii_reserve_at_least(mii_mempool_t mempool,
                                   unsigned *rdptr,
                                   int min_size)
{
  mempool_info_t *info = (mempool_info_t *)mempool;
  unsigned *wrptr = info->wrptr;

  if (!rdptr) {
    // There are no currenlty allocate packets so there is enough room
    return (mii_packet_t *)wrptr;
  }

  int space_left = (char *)rdptr - (char *)wrptr;

  if (space_left <= 0)
    space_left += (char *)info->end - (char *)info->start;

  if (space_left < min_size)
    return 0;

  return (mii_packet_t *)wrptr;
}

mii_packet_t *mii_reserve(mii_mempool_t mempool,
                          unsigned *rdptr,
                          unsigned **end_ptr)
{
  mempool_info_t *info = (mempool_info_t *)mempool;
  unsigned *wrptr = info->wrptr;

  if (rdptr > wrptr) {
    int space_left = (char *)rdptr - (char *)wrptr;
    if (space_left < MIN_USAGE) {
      *end_ptr = dummy_end_ptr;
      return dummy_packet;
    }
  } else  {
    // If the wrptr is after the rdptr then the should be at least
    // MIN_USAGE between the wrptr and the end of the buffer, therefore
    // at least MIN_USAGE space left
  }

  *end_ptr = (unsigned *)rdptr;
  return (mii_packet_t *)wrptr;
}

void mii_commit(mii_mempool_t mempool, unsigned *end_ptr)
{
  mempool_info_t *info = (mempool_info_t *) mempool;

#if 0 && (NUM_ETHERNET_PORTS > 1) && !defined(DISABLE_ETHERNET_PORT_FORWARDING)
  buf->forwarding = 0;
#endif

  if (end_ptr > info->last_safe_wrptr)
    end_ptr = info->start;

  info->wrptr = end_ptr;
}

void mii_add_packet(mii_packet_queue_t queue, mii_packet_t *buf)
{
  packet_queue_info_t *info = (packet_queue_info_t *)queue;
  unsigned wr_index = info->wr_index;

  info->ptrs[wr_index] = (unsigned *)buf;
  info->wr_index = increment_and_wrap_power_of_2(wr_index, ETHERNET_NUM_PACKET_POINTERS);
}

void mii_free_current(mii_packet_queue_t queue)
{
  packet_queue_info_t *info = (packet_queue_info_t *)queue;
  mii_free_index(queue, info->rd_index);
}

unsigned mii_free_index(mii_packet_queue_t queue, unsigned index)
{
  packet_queue_info_t *info = (packet_queue_info_t *)queue;

  if (info->rd_index == index) {
    // If this the oldest free entry then skip to the next used buffer
    info->rd_index = mii_move_my_rd_index(queue, index);
  }

  // Indicate that this entry is free - after the rd_index has been moved
  info->ptrs[index] = 0;

  return info->rd_index;
}

unsigned mii_init_my_rd_index(mii_packet_queue_t queue)
{
  packet_queue_info_t *info = (packet_queue_info_t *) queue;
  return info->rd_index;
}

void mii_move_rd_index(mii_packet_queue_t queue)
{
  packet_queue_info_t *info = (packet_queue_info_t *) queue;
  info->ptrs[info->rd_index] = 0;
  info->rd_index = increment_and_wrap_power_of_2(info->rd_index, ETHERNET_NUM_PACKET_POINTERS);
}

unsigned mii_move_my_rd_index(mii_packet_queue_t queue, unsigned rd_index)
{
  // Move the read index forward until a non-zero buffer is found or the entire
  // list is empty
  packet_queue_info_t *info = (packet_queue_info_t *)queue;

  while (1) {
    rd_index = increment_and_wrap_power_of_2(rd_index, ETHERNET_NUM_PACKET_POINTERS);

    if (rd_index == info->wr_index) {
      // All buffers free, done
      break;
    }

    if (info->ptrs[rd_index] != 0) {
      // Found a used buffer, done
      break;
    }
  }

  return rd_index;
}

mii_packet_t *mii_get_next_buf(mii_packet_queue_t queue)
{
  packet_queue_info_t *info = (packet_queue_info_t *)queue;
  return (mii_packet_t *) (info->ptrs[info->rd_index]);
}

mii_packet_t *mii_get_my_next_buf(mii_packet_queue_t queue, unsigned rd_index)
{
  packet_queue_info_t *info = (packet_queue_info_t *)queue;

  if (info->rd_index == info->wr_index) {
    // The buffer is either empty (pointer will be 0) or full (pointer will
    // be non-zero). In either case, must return NULL so that it won't be
    // processed.
    return NULL;
  }

  return (mii_packet_t *) (info->ptrs[rd_index]);
}

unsigned *mii_get_next_rdptr(mii_packet_queue_t queue_lp, mii_packet_queue_t queue_hp)
{
  packet_queue_info_t *info_lp = (packet_queue_info_t *)queue_lp;
  packet_queue_info_t *info_hp = (packet_queue_info_t *)queue_hp;

  // NOTE: The assumption is that the high priority traffic will be pulled out faster
  // than the low priority traffic and therefore if there are low priority pointers
  // they are the ones to use.
  if (info_lp->ptrs[info_lp->rd_index])
    return info_lp->ptrs[info_lp->rd_index];
  else
    return info_hp->ptrs[info_hp->rd_index];
}

unsigned *mii_get_rdptr(mii_packet_queue_t queue)
{
  packet_queue_info_t *info = (packet_queue_info_t *)queue;
  return info->ptrs[info->rd_index];
}

int mii_get_and_dec_transmit_count(mii_packet_t *buf)
{
  int count;
  if (!ETHERNET_USE_HARDWARE_LOCKS) {
    //    swlock_acquire(&tc_lock);
    assert(0);
  }
  else {
    hwlock_acquire(ethernet_memory_lock);
  }

  count = buf->tcount;
  if (count)
    buf->tcount = count - 1;

  if (!ETHERNET_USE_HARDWARE_LOCKS) {
    //    swlock_release(&tc_lock);
    assert(0);
  }
  else {
    hwlock_release(ethernet_memory_lock);
  }
  return count;
}
