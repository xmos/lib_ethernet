// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved

#include <xs1.h>
#include "mii_lite_driver.h"
#include "mii_lite_lld.h"
#include "hwtimer.h"
#include "xassert.h"
#include "print.h"
#include "mii_buffering.h"

// TODO: implement mii_driver straight in mii_lld.
void mii_lite_driver(in buffered port:32 p_rxd,
                     in port p_rxdv,
                     out buffered port:32 p_txd,
                     port p_mii_timing,
                     chanend c_in, chanend c_out)
{
  hwtimer_t tmr;
  mii_lite_lld(p_rxd, p_rxdv, p_txd,
               c_in, c_out, p_mii_timing, tmr);
}

#define POLY   0xEDB88320

extern void mii_lite_install_handler(struct mii_lite_data_t &this,
                                     int buffer_addr,
                                     chanend mii_channel,
                                     chanend c_notifications);

static int value_1(int address) {
  int ret_val;
  asm("ldw %0, %1[1]" : "=r" (ret_val) : "r" (address));
  return ret_val;
}

static int value_2(int address) {
  int ret_val;
  asm("ldw %0, %1[2]" : "=r" (ret_val) : "r" (address));
  return ret_val;
}

static int value_3(int address) {
  int ret_val;
  asm("ldw %0, %1[3]" : "=r" (ret_val) : "r" (address));
  return ret_val;
}

static int CRCBad(int base, int end) {
  unsigned int tail_bits = value_1(end);
  unsigned int tail_length = value_2(end);
  unsigned int part_crc = value_3(end);
  unsigned int length = end - base + (tail_length >> 3);
  switch (tail_length >> 2) {
    case 0:
    case 1:
      break;
    case 2:
      tail_bits >>= 24;
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      break;
    case 3:
      tail_bits >>= 20;
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      break;
    case 4:
      tail_bits >>= 16;
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      break;
    case 5:
      tail_bits >>= 12;
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      break;
    case 6:
      tail_bits >>= 8;
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      break;
    case 7:
      tail_bits >>= 4;
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      tail_bits = crc8shr(part_crc, tail_bits, POLY);
      break;
  }
  return ~part_crc == 0 ? length : 0;
}

static int packet_good(struct mii_lite_data_t &this, int base, int end) {
  int length = CRCBad(base, end);
  return length;
}

/* Buffer management. Each buffer consists of a single word that encodes
 * the length and the buffer status, and then (LENGTH+3)>>2 words. The
 * encoding is as follows: a positive number indicates a buffer that is in
 * use and the length is the positive number in bytes, a negative number
 * indicates a free buffer and the length is minus the negative number in
 * bytes, zero indicates that the buffer is the unused tail end of the
 * circular buffer; more allocated buffers are found wrapped around to the
 * head, one indicates that this is the write pointer.
 *
 * There are two circular buffers, denoted Bank 0 and Bank 1. Each buffer
 * has a free pointer, a write pointer, a lastsafe pointer, and a first
 * pointer. The first pointer is the address of the first word of memory,
 * the last safe pointer is the address of the last word where a full
 * packet can be stored. These pointers are constant. The write pointer
 * points to the place where the next packet is written (that is the word
 * past the length), the free pointer points to the place that could
 * potentially next be freed. The free pointer either points to an
 * allocated buffer, or it sits right behind the write pointer. The write
 * pointer either points to enough free space to allocate a buffer, or it
 * sits too close to the free pointer for there to be room for a packet.
 */

/* packet_in_lld (maintained by the LLD) remembers which buffer is being
 * filled right now; next_buffer (maintained byt Client_user.xc) stores which
 * buffer is to be filled next. When receiving a packet, packet_in_lld is
 * being filled with up to MAXPACKET bytes. On an interrupt, next_buffer is
 * being given to the LLD to be filled. The assembly level interrupt
 * routine leaves packet_in_lld to the contents of next_buffer (since that is
 * being filled in by the LLD), and the user level interrupt routine must
 * leave next_buffer to point to a fresh buffer.
 */

#define MAXPACKET 1530

static void set(int addr, int value) {
  asm("stw %0, %1[0]" :: "r" (value), "r" (addr));
}

static int get(int addr) {
  int value;
  asm("ldw %0, %1[0]" : "=r" (value) : "r" (addr));
  return value;
}

/* Called once on startup */

void mii_lite_buffer_init(struct mii_lite_data_t &this,
                          chanend c_in, chanend c_notifications,
                          chanend c_out, int buffer[], int number_words) {
  int address;
  this.notify_seen = 1;
  this.notify_last = 1;
  asm("add %0, %1, 0" : "=r" (address) : "r" (buffer));
  this.read_ptr[0] = this.first_ptr[0] = this.free_ptr[0] = address ;
  this.read_ptr[1] = this.first_ptr[1] = this.free_ptr[1] = address + ((number_words << 1) & ~3) ;
  this.wr_ptr[0] = this.free_ptr[0] + 4;
  this.wr_ptr[1] = this.free_ptr[1] + 4;
  set(this.free_ptr[0], 1);
  set(this.free_ptr[1], 1);
  this.last_safe_ptr[0] = this.free_ptr[1] - MAXPACKET;
  this.last_safe_ptr[1] = address + (number_words << 2) - MAXPACKET;
  this.next_buffer    = this.wr_ptr[1];
  this.mii_packets_overran = 0;
  this.refill_bank_number = 0;
  this.read_bank = 0;
  this.read_bank_rd_ptr = 0;
  this.read_bank_wr_ptr = 0;
  mii_lite_install_handler(this, this.wr_ptr[0], c_in, c_notifications);
  unsafe {
    this.mii_out_channel = (unsafe chanend) c_out;
  }
}


/* Called from interrupt handler */

void mii_notify(struct mii_lite_data_t &this, chanend c_notifications) {
  if (this.notify_last == this.notify_seen) {
    this.notify_last = !this.notify_last;
    outuchar(c_notifications, this.notify_last);
  }
}

select mii_notified(struct mii_lite_data_t &this, chanend c_notifications) {
case inuchar_byref(c_notifications, this.notify_seen):
  break;
}

#pragma unsafe arrays
{char * unsafe, unsigned, unsigned} mii_lite_get_in_buffer(struct mii_lite_data_t &this,
                                                           chanend c_notifications) {
  unsafe {
    if (this.read_bank_rd_ptr != this.read_bank_wr_ptr) {
      unsigned bank = (this.read_bank >> this.read_bank_rd_ptr) & 0x1;
      unsigned n_bytes = get(this.read_ptr[bank]);
      if (n_bytes == 0) {
        this.read_ptr[bank] = this.first_ptr[bank];
        n_bytes = get(this.read_ptr[bank]);
      }

      if (n_bytes != 1) {
        unsigned ret_val = this.read_ptr[bank] + 4;
        this.read_ptr[bank] += ((n_bytes + 3) & ~3) + 4;

        // Move the read bank pointer
        this.read_bank_rd_ptr = increment_and_wrap_power_of_2(this.read_bank_rd_ptr, 32);

        if (get(this.read_ptr[bank]) == 0) {
          this.read_ptr[bank] = this.first_ptr[bank];
        }

        if (this.read_bank_rd_ptr != this.read_bank_wr_ptr)
          mii_notify(this, c_notifications);

        unsigned time_stamp = get(ret_val);

        // Discount the CRC from the length
        return {(char * unsafe) (ret_val+4), n_bytes-4, time_stamp};

      }
    }
    return {(char * unsafe) 0, 0, 0};
  }
}

#pragma unsafe arrays
static void mii_commit_buffer(struct mii_lite_data_t &this, unsigned int current_buffer,
                            unsigned int length, chanend c_notifications) {
  int bn = current_buffer < this.first_ptr[1] ? 0 : 1;
  set(this.wr_ptr[bn]-4, length);                          // record length of current packet.
  this.wr_ptr[bn] = this.wr_ptr[bn] + ((length+3)&~3) + 4; // new end pointer.
  mii_notify(this, c_notifications);
  if (this.wr_ptr[bn] > this.last_safe_ptr[bn]) {          // This may be too far.
    if (this.free_ptr[bn] != this.first_ptr[bn]) {         // Test if head of buf is free
      set(this.wr_ptr[bn]-4, 0);                           // If so, record unused tail.
      this.wr_ptr[bn] = this.first_ptr[bn] + 4;            // and wrap to head, and record that
      set(this.wr_ptr[bn]-4, 1);                           // this is now the head of the queue.

      // Log which bank this packet was written to
      unsigned new_read_bank_wr_ptr = increment_and_wrap_power_of_2(this.read_bank_wr_ptr, 32);

      // If the pointers have overflowed the 32 slots then
      // drop the packet.
      if (this.read_bank_rd_ptr == new_read_bank_wr_ptr) {
        this.next_buffer = -1;
        this.refill_bank_number = bn;
        return;
      }

      this.read_bank &= ~(1 << this.read_bank_wr_ptr);
      this.read_bank |= bn << this.read_bank_wr_ptr;
      this.read_bank_wr_ptr = new_read_bank_wr_ptr;

      if (this.free_ptr[bn] - this.wr_ptr[bn] >= MAXPACKET) { // Test if there is room for a packet
        this.next_buffer = this.wr_ptr[bn];                   // if so, record packet pointer
        return;                                               // fall out - default is no room
      }
    } else {
      set(this.wr_ptr[bn]-4, 1);                          // this is still the head of the queue.
    }
  } else {                                                // room in tail.
    set(this.wr_ptr[bn]-4, 1);                            // record that this is now the head of the queue.

    // Log which bank this packet was written to
    unsigned new_read_bank_wr_ptr = increment_and_wrap_power_of_2(this.read_bank_wr_ptr, 32);

    // If the pointers have overflowed the 32 slots then
    // drop the packet.
    if (this.read_bank_rd_ptr == new_read_bank_wr_ptr) {
      this.next_buffer = -1;
      this.refill_bank_number = bn;
      return;
    }

    this.read_bank &= ~(1 << this.read_bank_wr_ptr);
    this.read_bank |= bn << this.read_bank_wr_ptr;
    this.read_bank_wr_ptr = new_read_bank_wr_ptr;

    if (this.wr_ptr[bn] > this.free_ptr[bn] ||            // Test if there is room for a packet
        this.free_ptr[bn] - this.wr_ptr[bn] >= MAXPACKET) {
      this.next_buffer = this.wr_ptr[bn];                 // if so, record packet pointer
      return;
    }
  }
  this.next_buffer = -1;                                  // buffer full - no more room for data.
  this.refill_bank_number = bn;
  return;
}

static void mii_reject_buffer(struct mii_lite_data_t &this, unsigned int current_buffer) {
    this.next_buffer = current_buffer;
}

#pragma unsafe arrays
void mii_lite_restart_buffer(struct mii_lite_data_t &this) {
  int bn;
  if (this.next_buffer != -1) {
    return;
  }
  bn = this.refill_bank_number;

  if (this.wr_ptr[bn] > this.last_safe_ptr[bn]) {      // This may be too far.
    if (this.free_ptr[bn] != this.first_ptr[bn]) {     // Test if head of buf is free
      set(this.wr_ptr[bn]-4, 0);                       // If so, record unused tail.
      this.wr_ptr[bn] = this.first_ptr[bn] + 4;        // and wrap to head, and record that
      set(this.wr_ptr[bn]-4, 1);                       // this is now the head of the queue.
      if (this.free_ptr[bn] - this.wr_ptr[bn] >= MAXPACKET) {// Test if there is room for packet
        this.next_buffer = this.wr_ptr[bn];            // if so, record packet pointer
      }
    }
  } else {                                             // room in tail.
    if (this.wr_ptr[bn] > this.free_ptr[bn] ||         // Test if there is room for a packet
        this.free_ptr[bn] - this.wr_ptr[bn] >= MAXPACKET) {
      this.next_buffer = this.wr_ptr[bn];              // if so, record packet pointer
    }
  }
}

#pragma unsafe arrays
void mii_lite_free_in_buffer(struct mii_lite_data_t &this, char * unsafe base0) {
  unsafe {
    int base = (int) base0;
    int bank_number = base < this.first_ptr[1] ? 0 : 1;
    int modified_free_ptr = 0;
    base -= 4;
    set(base-4, -get(base-4));
    while (1) {
      int l = get(this.free_ptr[bank_number]);
      if (l > 0) {
        break;
      }
      modified_free_ptr = 1;
      if (l == 0) {
        this.free_ptr[bank_number] = this.first_ptr[bank_number];
      } else {
        this.free_ptr[bank_number] += (((-l) + 3) & ~3) + 4;
      }
    }
    // Note - wrptr may have been stuck
  }
  mii_lite_restart_buffer(this);
}

static int global_offset;
int global_now;

void mii_time_stamp_init(unsigned offset) {
  int test_offset = 10000; // set to +/- 10000 for testing.
  global_offset = (offset + test_offset) & 0x3FFFF;
}

#pragma unsafe arrays
void mii_client_user(struct mii_lite_data_t &this, int base, int end, chanend c_notifications) {
  int length = packet_good(this, base, end);
  if (length >= 64) {
    mii_commit_buffer(this, base, length, c_notifications);
  } else {
    mii_reject_buffer(this, base);
  }
}

#pragma unsafe arrays
int mii_lite_out_packet(chanend c_out, int * unsafe b, int index, int length) {
  int a, rounded_length;
  int odd_bytes = length & 3;
  int precise;
  unsafe {
    a = (int) b;
    rounded_length = length >> 2;
    b[rounded_length+1] = tail_values[odd_bytes];
    b[rounded_length] &= (1 << (odd_bytes << 3)) - 1;
    b[rounded_length+2] = -rounded_length + 1;
    outuint(c_out, a + length - odd_bytes - 4);
  }
  precise = inuint(c_out);

  // 64 takes you from the start of the preamble to the start of the destination address
  return precise + 64;
}

#define assign(base,i,c)  asm("stw %0,%1[%2]"::"r"(c),"r"(base),"r"(i))
#define assignl(c,base,i) asm("ldw %0,%1[%2]"::"r"(c),"r"(base),"r"(i))

int mii_out_packet_(chanend c_out, int a, int length) {
  int rounded_length;
  int odd_bytes = length & 3;
  int precise;
  int x;

  rounded_length = length >> 2;
  assign(a, rounded_length+1, tail_values[odd_bytes]);
  assignl(x, a, rounded_length);
  assign(a, rounded_length, x & (1 << (odd_bytes << 3)) - 1);
  assign(a, rounded_length+2, -rounded_length + 1);
  outuint(c_out, a + length - odd_bytes - 4);

  precise = inuint(c_out);

  // 64 takes you from the start of the preamble to the start of the destination address
  return precise + 64;
}

void mii_lite_out_packet_done(chanend c_out) {
  chkct(c_out, 1);
}

void mii_lite_out_init(chanend c_out) {
  chkct(c_out, 1);
}

static void drain(chanend c) {
  outct(c, 1);
  while(!testct(c)) {
    inuchar(c);
  }
  chkct(c, 1);
}

void mii_close(chanend c_notifications, chanend c_in, chanend c_out) {
  asm("clrsr 2");         // disable interrupts
  drain(c_notifications); // disconnect channel to ourselves
  outct(c_out, 1);        // disconnect channel to output - stops mii
  chkct(c_out, 1);
  drain(c_in);            // disconnect input side.
}

