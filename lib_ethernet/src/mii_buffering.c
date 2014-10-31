#include "mii_buffering.h"
#include "debug_print.h"

#define MII_PACKET_HEADER_SIZE (sizeof(mii_packet_t) - ((ETHERNET_MAX_PACKET_SIZE+3)/4)*4)
#define MIN_USAGE (MII_PACKET_HEADER_SIZE+sizeof(malloc_hdr_t)+4*10)

#if ETHERNET_USE_HARDWARE_LOCKS
hwlock_t ethernet_memory_lock = 0;
#endif

static unsigned dummy_buf[(sizeof(mempool_info_t) +
                           sizeof(malloc_hdr_t) +
                           MII_PACKET_HEADER_SIZE +
                           4*10)/4];

static mii_packet_t *dummy_packet;
static unsigned * dummy_end_ptr;

static void init_dummy_buf()
{
  mempool_info_t *info = (mempool_info_t *) (void *) &dummy_buf[0];
  info->start = (int *) (((char *) dummy_buf) + sizeof(mempool_info_t));
  info->end = (int *) (((char *) dummy_buf) + sizeof(dummy_buf) - 4);
  info->rdptr = info->start;
  info->wrptr = info->start;
  *(info->start) = 0;
  *(info->end) = (int) (info->start);
#if !ETHERNET_USE_HARDWARE_LOCKS
  swlock_init(&info->lock);
#else
  if (ethernet_memory_lock == 0) {
    ethernet_memory_lock = hwlock_alloc();
  }
#endif
  dummy_packet = (mii_packet_t *) ((char *) info->wrptr + (sizeof(malloc_hdr_t)));
  dummy_end_ptr = (unsigned *) ((char*) dummy_packet + MII_PACKET_HEADER_SIZE + 4*10);
  ((malloc_hdr_t *) (info->wrptr))->info = info;
}

mii_mempool_t mii_init_mempool(unsigned * buf, int size)
{
  if (size < 4)
    return 0;
  if (dummy_buf[0] == 0)
    init_dummy_buf();
  mempool_info_t *info = (mempool_info_t *) buf;
  info->start = (int *) (((char *) buf) + sizeof(mempool_info_t));
  info->end = (int *) (((char *) buf) + size - 4);
  info->rdptr = info->start;
  info->wrptr = info->start;
  *(info->start) = 0;
  *(info->end) = (int) (info->start);
#if !ETHERNET_USE_HARDWARE_LOCKS
  swlock_init(&info->lock);
#else
  if (ethernet_memory_lock == 0) {
    ethernet_memory_lock = hwlock_alloc();
  }
#endif
  return ((mii_mempool_t) info);
}

unsigned *mii_get_wrap_ptr(mii_mempool_t mempool)
{
  mempool_info_t *info = (mempool_info_t *) mempool;
  return (unsigned *) (info->end);
}

mii_packet_t *mii_reserve_at_least(mii_mempool_t mempool,
                                   int min_size)
{
  mempool_info_t *info = (mempool_info_t *) mempool;
  int *rdptr = info->rdptr;
  int *wrptr = info->wrptr;
  malloc_hdr_t *hdr;
  int space_left;

  space_left = (char *) rdptr - (char *) wrptr;

  if (space_left <= 0)
    space_left += (char *) info->end - (char *) info->start;

  if (space_left < min_size)
    return 0;

  hdr = (malloc_hdr_t *) wrptr;
  hdr->info = info;

  return (mii_packet_t *) (wrptr+(sizeof(malloc_hdr_t)>>2));
}

mii_packet_t *mii_reserve(mii_mempool_t mempool,
                          unsigned **end_ptr)
{
  mempool_info_t *info = (mempool_info_t *) mempool;
  int *rdptr = info->rdptr;
  int *wrptr = info->wrptr;
  malloc_hdr_t *hdr;
  int space_left;

  if (rdptr > wrptr) {
    space_left = (char *) rdptr - (char *) wrptr;
    if (space_left < MIN_USAGE) {
      *end_ptr = dummy_end_ptr;
      return dummy_packet;
    }
  } else  {
    // If the wrptr is after the rdptr then the should be at least
    // MIN_USAGE between the wrptr and the end of the buffer, therefore
    // at least MIN_USAGE space left
  }

  hdr = (malloc_hdr_t *) wrptr;
  hdr->info = info;

  *end_ptr = (unsigned *) rdptr;
  return (mii_packet_t *) (wrptr+(sizeof(malloc_hdr_t)>>2));
}

void mii_commit(mii_packet_t *buf, unsigned *endptr0)
{
  int *end_ptr = (int *) endptr0;
  malloc_hdr_t *hdr = (malloc_hdr_t *) ((char *) buf - sizeof(malloc_hdr_t));
  mempool_info_t *info = (mempool_info_t *) hdr->info;
  mii_packet_t *pkt;
  int *end = info->end;

  pkt = (mii_packet_t *) buf;
  pkt->stage = 0;

#if 0 && (NUM_ETHERNET_PORTS > 1) && !defined(DISABLE_ETHERNET_PORT_FORWARDING)
  pkt->forwarding = 0;
#endif

  if (((int) (char *) end - (int) (char *) end_ptr) < MIN_USAGE)
    end_ptr = info->start;

  hdr->next = (int) end_ptr;

  info->wrptr = end_ptr;

  return;
}

void mii_free(mii_packet_t *buf) {
  malloc_hdr_t *hdr = (malloc_hdr_t *) ((char *) buf - sizeof(malloc_hdr_t));
  mempool_info_t *info = (mempool_info_t *) hdr->info;

#ifndef ETHERNET_USE_HARDWARE_LOCKS
  swlock_acquire(&info->lock);
#else
  hwlock_acquire(ethernet_memory_lock);
#endif

  while (1) {
	// If we are freeing the oldest packet in the fifo then actually
	// move the rd_ptr.
    if ((char *) hdr == (char *) info->rdptr) {
      malloc_hdr_t *old_hdr = hdr;

      int next = hdr->next;
      if (next < 0) next = -next;

      // Move to the next packet
      hdr = (malloc_hdr_t *) next;
      info->rdptr = (int *) hdr;

      // Mark as empty
      old_hdr->next = 0;

      // If we have an unfreed packet, or have hit the end of the
      // mempool fifo then stop (order of test is important due to lock
      // free mii_commit)
      if ((char *) hdr == (char *) info->wrptr || hdr->next > 0) {
          break;
      }
    } else {
      // If this isn't the oldest packet in the queue then just mark it
      // as free by making the next = -next
      hdr->next = -(hdr->next);
      break;
    }
  };

#ifndef ETHERNET_USE_HARDWARE_LOCKS
  swlock_release(&info->lock);
#else
  hwlock_release(ethernet_memory_lock);
#endif
}


mii_rdptr_t mii_init_my_rdptr(mii_mempool_t mempool)
{
  mempool_info_t *info = (mempool_info_t *) mempool;
  return (mii_rdptr_t) info->rdptr;
}


mii_rdptr_t mii_update_my_rdptr(mii_mempool_t mempool, mii_rdptr_t rdptr0)
{
  int *rdptr = (int *) rdptr0;
  malloc_hdr_t *hdr;
  int next;

  hdr = (malloc_hdr_t *) rdptr;
  next = hdr->next;

#ifdef MII_MALLOC_ASSERT
  // Should always be a positive next pointer
  if (next <= 0) {
	  __builtin_trap();
  }
#endif

  return (mii_rdptr_t) next;
}

mii_packet_t *mii_get_my_next_buf(mii_mempool_t mempool, mii_rdptr_t rdptr0)
{
  mempool_info_t *info = (mempool_info_t *) mempool;
  int *rdptr = (int *) rdptr0;
  int *wrptr = info->wrptr;

  if (rdptr == wrptr)
    return 0;

  return (mii_packet_t *) ((char *) rdptr + sizeof(malloc_hdr_t));
}

mii_packet_t *mii_get_next_buf(mii_mempool_t mempool)
{
  mempool_info_t *info = (mempool_info_t *) mempool;
  int *rdptr = info->rdptr;
  int *wrptr = info->wrptr;

  if (rdptr == wrptr)
    return 0;


  return (mii_packet_t *) ((char *) rdptr + sizeof(malloc_hdr_t));
}

unsigned *mii_packet_get_wrap_ptr(mii_packet_t *buf)
{
  malloc_hdr_t *hdr = (malloc_hdr_t *) (((char *) buf) - sizeof(malloc_hdr_t));
  mempool_info_t *info = hdr->info;
  return (unsigned *) (info->end);
}


int mii_get_and_dec_transmit_count(mii_packet_t *buf)
{
  int count;
#ifndef ETHERNET_USE_HARDWARE_LOCKS
  swlock_acquire(&tc_lock);
#else
  hwlock_acquire(ethernet_memory_lock);
#endif
  count = buf->tcount;
  if (count)
    buf->tcount = count - 1;
#ifndef ETHERNET_USE_HARDWARE_LOCKS
  swlock_release(&tc_lock);
#else
  hwlock_release(ethernet_memory_lock);
#endif
  return count;
}
