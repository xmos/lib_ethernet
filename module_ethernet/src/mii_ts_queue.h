#ifndef __mii_ts_queue_h__
#define __mii_ts_queue_h__
#include "mii_buffering.h"

#ifdef __XC__
extern "C" {
#endif

typedef struct mii_ts_queue_info_t {
  int lock;
  int rdIndex;
  int wrIndex;
  int num_entries;
  unsigned *fifo;
} mii_ts_queue_info_t;

typedef mii_ts_queue_info_t *mii_ts_queue_t;

mii_ts_queue_t mii_ts_queue_init(mii_ts_queue_info_t *q, unsigned *buf, int n);

void mii_ts_queue_add_entry(mii_ts_queue_t q, mii_packet_t *buf);

#ifdef __XC__
} // extern "C"
#endif

#endif // __mii_ts_queue_h__
