// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#ifndef __mii_buffering_h__
#define __mii_buffering_h__
#include "ethernet.h"
#include "default_ethernet_conf.h"
#include "swlock.h"
#include "hwlock.h"
#include "mii_buffering_defines.h"

#ifdef __XC__
extern "C" {
#endif

inline unsigned increment_and_wrap_to_zero(unsigned value, unsigned max) {
  value++;
  value *= (value != max);
  return value;
}

inline unsigned increment_and_wrap_power_of_2(unsigned value, unsigned max) {
  value = (value + 1) % max;
  return value;
}

// Allocate an extra two words of data per packet buffer because when the RGMII
// receiver gets a frame that just exceeds the maximum size it will write up to
// these extra two words of data that are returned by the ENDIN.
#define MII_PACKET_DATA_BYTES (ETHERNET_MAX_PACKET_SIZE + 8)

// NOTE: If this structure is modified then the MII_PACKET_HEADER_BYTES define in
//       mii_buffering_defines.h
typedef struct mii_packet_t {
  int length;           //!< The length of the packet in bytes
  int timestamp;        //!< The transmit or receive timestamp
  int filter_result;    //!< The bitfield of filter passes
  int src_port;         //!< The ethernet port which a packet arrived on
  int timestamp_id;     //!< Client channel number which is waiting for a
                        //   Tx timestamp
  int tcount;           //!< Number of remaining clients who need to be send
                        //   this RX packet minus one
  int crc;              //!< The calculated CRC
  int forwarding;       //!< A bitfield for tracking forwarding of the packet
                        //   to other ports
  int vlan_tagged;      //!< Whether the packet is VLAN tagged or not
  unsigned filter_data; //!< Word of data returned by the mac filter
  unsigned int data[(MII_PACKET_DATA_BYTES+3)/4];
} mii_packet_t;

/*
 * The mempool is a structure that contains a block of memory that is used to store
 * multiple packets. Data is written at the wrptr. The packets themselves are logged
 * in the packet_queue_info_t structure below.
 *
 * The packets written to the buffer are written within mii_packet_t structures (see
 * above). The buffering scheme requires the program to be able to write to anywhere
 * in the mii_packet_t header and hence the packets can only start a certain distance
 * from the end of the buffer. The last_safe_wrptr is an optimisation for critical
 * paths in the rx MAC.
 *
 * The end of the buffer is used to contain a pointer to the start such that when the
 * end is reached it is a simple load operation from that address to get the start
 * address.
 */ 
typedef struct mempool_info_t {
  unsigned *wrptr;
  unsigned *start;
  unsigned *end;
  unsigned *last_safe_wrptr;
  swlock_t lock;
} mempool_info_t;

/*
 * A structure which contains a number of packet pointers in a queue. The wr_index is
 * where new packets are added and the rd_index is where the oldest packets are read.
 * The assumption is made that the ptrs[] memory is kept full of 0s unless in use.
 * This assumption is used for checking whether the queue is full and empty without
 * having to do any pointer calculations.
 *
 * Having the number of pointers a power of 2 is used to optimise the pointer wrapping.
 */
typedef struct packet_queue_info_t {
  unsigned rd_index;
  unsigned wr_index;
  unsigned *ptrs[ETHERNET_NUM_PACKET_POINTERS];
} packet_queue_info_t;

/* Typedefs for use more readily within XC */
typedef unsigned * mii_mempool_t;
typedef unsigned * mii_buffer_t;
typedef unsigned * mii_rdptr_t;
typedef unsigned * mii_packet_queue_t;

void mii_init_packet_queue(mii_packet_queue_t queue);
mii_mempool_t mii_init_mempool(unsigned *buffer, int size);
void mii_init_lock();

int mii_packet_queue_full(mii_packet_queue_t queue);

unsigned *mii_get_wrap_ptr(mii_mempool_t mempool);

mii_packet_t *mii_reserve(mii_mempool_t mempool,
                          unsigned *rdptr,
                          unsigned **end_ptr);

mii_packet_t *mii_reserve_at_least(mii_mempool_t mempool,
                                   unsigned *rdptr,
                                   int min_size);

void mii_commit(mii_mempool_t mempool, unsigned *endptr0);
void mii_add_packet(mii_packet_queue_t queue, mii_packet_t *buf);

void mii_free_current(mii_packet_queue_t queue);
unsigned mii_free_index(mii_packet_queue_t queue, unsigned index);

unsigned mii_init_my_rd_index(mii_packet_queue_t queue);
void mii_move_rd_index(mii_packet_queue_t queue);
unsigned mii_move_my_rd_index(mii_packet_queue_t queue, unsigned rd_index);
mii_packet_t *mii_get_next_buf(mii_packet_queue_t queue);
mii_packet_t *mii_get_my_next_buf(mii_packet_queue_t queue, unsigned rd_index);

unsigned *mii_get_next_rdptr(mii_packet_queue_t queue0,
                             mii_packet_queue_t queue1);
unsigned *mii_get_rdptr(mii_packet_queue_t queue);

int mii_get_and_dec_transmit_count(mii_packet_t *buf);

extern hwlock_t ethernet_memory_lock;

#ifdef __XC__
} // extern "C"
#endif


#endif //__mii_buffering_h__
