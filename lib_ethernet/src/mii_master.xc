// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>
#include "mii_master.h"
#include <xs1.h>
#include <print.h>
#include <stdlib.h>
#include <syscall.h>
#include <xclib.h>
#include "mii_buffering.h"
#include "debug_print.h"
#include "mii_ethernet_conf.h"
#include "mii_common_lld.h"
#include "string.h"

// As of the v12/13 xTIMEcomper tools. The compiler schedules code around a
// bit too much which violates the timing constraints. This change to the
// crc32 makes it a barrier to scheduling. This is not really
// recommended practice since it inhibits the compiler in a bit of a hacky way,
// but is perfectly safe.
#undef crc32
#define crc32(a, b, c) {__builtin_crc32(a, b, c); asm volatile (""::"r"(a):"memory");}


#ifndef ETHERNET_ENABLE_FULL_TIMINGS
#define ETHERNET_ENABLE_FULL_TIMINGS (1)
#endif

// Timing tuning constants
#define PAD_DELAY_RECEIVE    0
#define PAD_DELAY_TRANSMIT   0
#define CLK_DELAY_RECEIVE    0
#define CLK_DELAY_TRANSMIT   7  // Note: used to be 2 (improved simulator?)
// After-init delay (used at the end of mii_init)
#define PHY_INIT_DELAY 10000000

// The inter-frame gap is 96 bit times (1 clock tick at 100Mb/s). However,
// the EOF time stamp is taken when the last but one word goes into the
// transfer register, so that leaves 96 bits of data still to be sent
// on the wire (shift register word, transfer register word, crc word).
// In the case of a non word-aligned transfer compensation is made for
// that in the code at runtime.
// The adjustment is due to the fact that the instruction
// that reads the timer is the next instruction after the out at the
// end of the packet and the timer wait is an instruction before the
// out of the pre-amble
#define ETHERNET_IFS_AS_REF_CLOCK_COUNT  (96 + 96 - 10)

// Receive timing constraints
#if ETHERNET_ENABLE_FULL_TIMINGS
#pragma xta command "config Terror on"
#pragma xta command "remove exclusion *"

#pragma xta command "add exclusion mii_rx_begin"
#pragma xta command "add exclusion mii_eof_case_1"
#pragma xta command "add exclusion mii_eof_case_2"
//#pragma xta command "add exclusion mii_wait_for_buffers"

// Start of frame to first word is 32 bits = 320ns
#pragma xta command "analyze endpoints mii_rx_sof mii_rx_first_words"
#pragma xta command "set required - 320 ns"

// Have to be commented out due to BUG 16264
//#pragma xta command "add exclusion mii_rx_sof"
//#pragma xta command "analyze endpoints mii_rx_first_words mii_rx_first_words"
//#pragma xta command "set required - 300 ns"

//#pragma xta command "analyze endpoints mii_rx_first_words mii_rx_word"
//#pragma xta command "set required - 320 ns"

#pragma xta command "analyze endpoints mii_rx_word mii_rx_word"
#pragma xta command "set required - 300 ns"

// The end of frame timing is 12 octets IFS + 7 octets preamble + 1 nibble preamble = 156 bits - 1560ns
//
// note: the RXDV will come low with the start of the pre-amble, but the code
//       checks for a valid RXDV and then starts hunting for the 'D' nibble at
//       the end of the pre-amble, so we don't need to spot the rising edge of
//       the RXDV, only the point where RXDV is valid and there is a 'D' on the
//       data lines.
#pragma xta command "remove exclusion *"
#pragma xta command "add exclusion mii_rx_after_preamble"
#pragma xta command "add exclusion mii_rx_eof"
#pragma xta command "add exclusion mii_rx_word"
#pragma xta command "add exclusion mii_reserve_hp"
#pragma xta command "analyze endpoints mii_rx_eof mii_rx_sof"
#pragma xta command "set required - 1560 ns"

#if ETHERNET_SUPPORT_HP_QUEUES
#pragma xta command "remove exclusion mii_reserve_hp"
#pragma xta command "add exclusion mii_reserve_lp"
#pragma xta command "analyze endpoints mii_rx_eof mii_rx_sof"
#pragma xta command "set required - 1560 ns"
#endif

#endif
// check the transmit interframe space.  It should ideally be quite close to 1560, which will
// allow the timer check to control the transmission rather than being instruction time bound

//#pragma xta command "remove exclusion *"
//#pragma xta command "add exclusion mii_tx_sof"
//#pragma xta command "add exclusion mii_tx_buffer_not_marked_for_transmission"
//#pragma xta command "add exclusion mii_tx_not_valid_to_transmit"

//#pragma xta command "analyze endpoints mii_tx_end mii_tx_start"
//#pragma xta command "set required - 1560 ns"

void mii_master_init(in port p_rxclk, in buffered port:32 p_rxd, in port p_rxdv,
                     clock clk_rx,
                     in port p_txclk, out port p_txen, out buffered port:32 p_txd,
                     clock clk_tx)
{
  set_port_use_on(p_rxclk);
  p_rxclk :> int x;
  set_port_use_on(p_rxd);
  set_port_use_on(p_rxdv);

  set_pad_delay(p_rxclk, PAD_DELAY_RECEIVE);

  set_port_strobed(p_rxd);
  set_port_slave(p_rxd);

  set_clock_on(clk_rx);
  set_clock_src(clk_rx, p_rxclk);
  set_clock_ready_src(clk_rx, p_rxdv);
  set_port_clock(p_rxd, clk_rx);
  set_port_clock(p_rxdv, clk_rx);

  set_clock_rise_delay(clk_rx, CLK_DELAY_RECEIVE);

  start_clock(clk_rx);

  clearbuf(p_rxd);

  set_port_use_on(p_txclk);
  set_port_use_on(p_txd);
  set_port_use_on(p_txen);
  //  set_port_use_on(p_txer);

  set_pad_delay(p_txclk, PAD_DELAY_TRANSMIT);

  p_txd <: 0;
  p_txen <: 0;
  //  p_txer <: 0;
  sync(p_txd);
  sync(p_txen);
  //  sync(p_txer);

  set_port_strobed(p_txd);
  set_port_master(p_txd);
  clearbuf(p_txd);

  set_port_ready_src(p_txen, p_txd);
  set_port_mode_ready(p_txen);

  set_clock_on(clk_tx);
  set_clock_src(clk_tx, p_txclk);
  set_port_clock(p_txd, clk_tx);
  set_port_clock(p_txen, clk_tx);

  set_clock_fall_delay(clk_tx, CLK_DELAY_TRANSMIT);

  start_clock(clk_tx);

  clearbuf(p_txd);
}

unsafe void mii_master_rx_pins(mii_mempool_t rxmem_hp,
                               mii_mempool_t rxmem_lp,
                               in port p_mii_rxdv,
                               in buffered port:32 p_mii_rxd,
                               in buffered port:1 p_mii_rxer,
                               streaming chanend c)
{
  timer tmr;
  unsigned * unsafe wrap_ptr;
  unsigned * unsafe wrap_ptr_hp;

  volatile unsigned * unsafe error_ptr = mii_setup_error_port(p_mii_rxer);

  if (!ETHERNET_SUPPORT_HP_QUEUES)
    rxmem_hp = 0;

  /* Set up the wrap markers for the two memory buffers. These are the
     points at which we must wrap data back to the beginning of the buffer */
  wrap_ptr = mii_get_wrap_ptr(rxmem_lp);

  if (rxmem_hp)
    wrap_ptr_hp = mii_get_wrap_ptr(rxmem_hp);

  /* Make sure we do not start in the middle of a packet */
  p_mii_rxdv when pinseq(0) :> int lo;

    /* Grab buffers to read the packet into. mii_reserve always returns a
       buffer we can use (though it may be a dummy buffer that gets thrown
       away later if we are out of buffer space). */

  unsigned * unsafe end_ptr, * unsafe end_ptr_hp;
  mii_packet_t * unsafe buf_lp = mii_reserve(rxmem_lp, end_ptr);
  mii_packet_t * unsafe buf_hp = null;
  if (rxmem_hp)
    buf_hp = mii_reserve(rxmem_hp, end_ptr_hp);

  while (1) {
    unsigned word;
    unsigned num_rx_words = 0;

    mii_packet_t * unsafe buf = buf_lp;

    unsigned crc = 0x9226F562;
    unsigned poly = 0xEDB88320;
    unsigned * unsafe dptr;

    /* Wait for the start of the packet and timestamp it */
    unsigned sfd_preamble;
    #pragma xta endpoint "mii_rx_sof"
    p_mii_rxd when pinseq(0xD) :> sfd_preamble;

    if (((sfd_preamble >> 24) & 0xFF) != 0xD5) {
      // Corrupt the CRC so that the packet is discarded
      crc = 0;
    }

    #pragma xta endpoint "mii_rx_after_preamble"
    unsigned time;
    tmr :> time;

    // Enable interrupts
    asm("setsr 0x2");

    unsigned end_of_frame = 0;
    unsigned header_done = 0;
    do {
      /* Read in the first 3 words of the packet into the header array.
         This gets copied into the packet buffer later */
      select {
#pragma xta endpoint "mii_rx_first_words"
      case p_mii_rxd :> word:
        if (num_rx_words < 3) {
          buf_lp->data[num_rx_words] = word;
          if (rxmem_hp)
            buf_hp->data[num_rx_words] = word;

          crc32(crc, word, poly);
        } else {
          unsigned short etype = (unsigned short) word;
          crc32(crc, word, poly);
          if (rxmem_hp && etype == 0x0081) {
            buf = buf_hp;
            wrap_ptr = wrap_ptr_hp;
            end_ptr = end_ptr_hp;
          }
          buf->data[3] = word;
          buf->timestamp = time;
          dptr = &buf->data[4];
          header_done = 1;
        }
        num_rx_words++;
        break;
      case p_mii_rxdv when pinseq(0) :> int:
#pragma xta label "mii_eof_case_1"
        header_done = 1;
        end_of_frame = 1;
        break;
      }
    } while (!header_done);

    if (end_of_frame)
      continue;

    do {
     select
       {
#pragma xta endpoint "mii_rx_word"
       case p_mii_rxd :> word:
         *dptr = word;
         crc32(crc, word, poly);
         if (dptr != end_ptr) {
           dptr++;
           if (dptr == wrap_ptr)
             dptr = (unsigned * unsafe) *dptr;
         }
         num_rx_words++;
         break;
#pragma xta endpoint "mii_rx_eof"
      case p_mii_rxdv when pinseq(0) :> int:
        {
#pragma xta label "mii_eof_case_2"
          end_of_frame = 1;
          break;
        }
      }
    } while (!end_of_frame);

    // Clear interrupts
    asm("clrsr 0x2");

    if (*error_ptr) {
      endin(p_mii_rxd);
      p_mii_rxd :> void;
      *error_ptr = 0;
      continue;
    }

#pragma xta label "mii_rx_begin"
    unsigned taillen = endin(p_mii_rxd);
    const unsigned num_rx_bytes_minus_crc = (num_rx_words-1)*sizeof(word) + (taillen>>3);
    buf->length = num_rx_bytes_minus_crc;

    // Ensure that the mask is byte-aligned
    unsigned mask = ~0U >> (taillen & ~0x7);

    unsigned tail;
    p_mii_rxd :> tail;

    // Correct for non byte-aligned frames
    if (taillen & 0x7)
      tail <<= taillen & 0x7;

    /* Mask out junk bits in last input */
    tail &= ~mask;

    /* Incorporate tailbits of input data,
       see https://github.com/xcore/doc_tips_and_tricks for details. */
    { tail, crc } = mac(crc, mask, tail, crc);
    crc32(crc, tail, poly);

    buf->crc = crc;

    if (dptr != end_ptr) {
      /* We don't store the last word since it contains the CRC and
         we don't need it from this point on. */
      c <: buf;
      mii_commit(buf, dptr);
    }

    if (rxmem_hp && buf == buf_hp) {
#pragma xta label "mii_reserve_hp"
      buf_hp = mii_reserve(rxmem_hp, end_ptr_hp);
    }
    else {
#pragma xta label "mii_reserve_lp"
      buf_lp = mii_reserve(rxmem_lp, end_ptr);
    }
  }

  return;
}


////////////////////////////////// TRANSMIT ////////////////////////////////

// Transmit timing constraints

#pragma xta command "remove exclusion *"
#pragma xta command "add exclusion mii_tx_start"
#pragma xta command "add exclusion mii_tx_end"

#pragma xta command "add loop mii_tx_loop 1"

#pragma xta command "analyze endpoints mii_tx_sof mii_tx_first_word"
#pragma xta command "set required - 640 ns"

#pragma xta command "analyze endpoints mii_tx_first_word mii_tx_word"
#pragma xta command "set required - 320 ns"

#pragma xta command "analyze endpoints mii_tx_word mii_tx_word"
#pragma xta command "set required - 320 ns"

#pragma xta command "add loop mii_tx_loop 0"

#pragma xta command "analyze endpoints mii_tx_word mii_tx_final_partword_3"
#pragma xta command "set required - 320 ns"

#pragma xta command "add exclusion mii_tx_final_partword_3"
#pragma xta command "analyze endpoints mii_tx_word mii_tx_final_partword_2"
#pragma xta command "set required - 320 ns"

#pragma xta command "add exclusion mii_tx_final_partword_2"
#pragma xta command "analyze endpoints mii_tx_word mii_tx_final_partword_1"
#pragma xta command "set required - 320 ns"

#pragma xta command "remove exclusion mii_tx_end"
#pragma xta command "add exclusion mii_tx_final_partword_1"
#pragma xta command "analyze endpoints mii_tx_word mii_tx_end"
#pragma xta command "set required - 320 ns"

#pragma xta command "remove exclusion mii_tx_final_partword_3"
#pragma xta command "remove exclusion mii_tx_final_partword_2"
#pragma xta command "remove exclusion mii_tx_final_partword_1"

#pragma xta command "analyze endpoints mii_tx_final_partword_3 mii_tx_final_partword_2"
#pragma xta command "set required - 80 ns"

#pragma xta command "analyze endpoints mii_tx_final_partword_2 mii_tx_final_partword_1"
#pragma xta command "set required - 80 ns"

#pragma xta command "analyze endpoints mii_tx_final_partword_1 mii_tx_end"
#pragma xta command "set required - 80 ns"



#undef crc32
#define crc32(a, b, c) {__builtin_crc32(a, b, c);}

#ifndef MII_TX_TIMESTAMP_END_OF_PACKET
#define MII_TX_TIMESTAMP_END_OF_PACKET (0)
#endif

unsafe unsigned mii_transmit_packet(mii_packet_t * unsafe buf,
                                                out buffered port:32 p_mii_txd,
                                                timer tmr, unsigned &ifg_time)
{
  unsigned time;
  register const unsigned poly = 0xEDB88320;
  unsigned int crc = 0;
  unsigned * unsafe dptr;
  int i=0;
  int word_count = buf->length >> 2;
  int tail_byte_count = buf->length & 3;
  unsigned * unsafe wrap_ptr;
  dptr = &buf->data[0];
  wrap_ptr = mii_packet_get_wrap_ptr(buf);

  // Check that we are out of the inter-frame gap
#pragma xta endpoint "mii_tx_start"
  tmr when timerafter(ifg_time) :> ifg_time;

#pragma xta endpoint "mii_tx_sof"
  p_mii_txd <: 0x55555555;
  p_mii_txd <: 0xD5555555;

  if (!MII_TX_TIMESTAMP_END_OF_PACKET && buf->timestamp_id) {
    tmr :> time;
  }

#pragma xta endpoint "mii_tx_first_word"
  unsigned word = *dptr;
  p_mii_txd <: *dptr;
  dptr++;
  i++;
  crc32(crc, ~word, poly);

  do {
#pragma xta label "mii_tx_loop"
    unsigned word = *dptr;
    dptr++;
    if (dptr == wrap_ptr)
      dptr = (unsigned *) *dptr;
    i++;
    crc32(crc, word, poly);
#pragma xta endpoint "mii_tx_word"
    p_mii_txd <: word;
    tmr :> ifg_time;
  } while (i < word_count);

  if (MII_TX_TIMESTAMP_END_OF_PACKET && buf->timestamp_id) {
    tmr :> time;
  }

  if (tail_byte_count) {
    unsigned word = *dptr;
    switch (tail_byte_count)
      {
      default:
        __builtin_unreachable();
        break;
#pragma fallthrough
      case 3:
#pragma xta endpoint "mii_tx_final_partword_3"
        partout(p_mii_txd, 8, word);
        word = crc8shr(crc, word, poly);
#pragma fallthrough
      case 2:
#pragma xta endpoint "mii_tx_final_partword_2"
        partout(p_mii_txd, 8, word);
        word = crc8shr(crc, word, poly);
      case 1:
#pragma xta endpoint "mii_tx_final_partword_1"
        partout(p_mii_txd, 8, word);
        crc8shr(crc, word, poly);
        break;
      }
  }
  crc32(crc, ~0, poly);
#pragma xta endpoint "mii_tx_end"
  p_mii_txd <: crc;
  return time;
}


unsafe void mii_master_tx_pins(mii_mempool_t hp_queue,
                               mii_mempool_t lp_queue,
                               mii_ts_queue_t ts_queue_lp,
                               out buffered port:32 p_mii_txd,
                               int enable_shaper,
                               volatile int * unsafe idle_slope)
{
  int credit = 0;
  int credit_time;
  timer tmr;
  unsigned ifg_time;

  if (!ETHERNET_SUPPORT_HP_QUEUES)
    hp_queue = 0;

  if (!ETHERNET_SUPPORT_TRAFFIC_SHAPER)
    enable_shaper = 0;

  if (hp_queue && enable_shaper)
    tmr :> credit_time;

  tmr :> ifg_time;

  while (1) {
#pragma xta label "mii_tx_main_loop"
    mii_packet_t * unsafe buf = null;
    int bytes_left;

    int stage;
    int prev_credit_time;
    int elapsed;
    mii_ts_queue_t *p_ts_queue = null;

    if (hp_queue)
      buf = mii_get_next_buf(hp_queue);

    if (enable_shaper) {
      if (buf && buf->stage == MII_STAGE_FILTERED) {

        if (credit < 0) {
          prev_credit_time = credit_time;
          tmr :> credit_time;

          elapsed = credit_time - prev_credit_time;
          credit += elapsed * (*idle_slope);
        }

        if (credit < 0)
          buf = 0;
        else {
          int len = buf->length;
          credit = credit - len << (MII_CREDIT_FRACTIONAL_BITS+3);
        }

      }
      else {
        if (credit >= 0)
          credit = 0;
        tmr :> credit_time;
      }
    }

    if (!hp_queue || !buf || buf->stage != MII_STAGE_FILTERED) {
      buf = mii_get_next_buf(lp_queue);
      p_ts_queue = &ts_queue_lp;
    }

    if (!buf) {
#pragma xta endpoint "mii_tx_not_valid_to_transmit"
      continue;
    }

    if (buf->stage != MII_STAGE_FILTERED) {
#pragma xta endpoint "mii_tx_buffer_not_marked_for_transmission"
      continue;
    }

    unsigned time = mii_transmit_packet(buf, p_mii_txd, tmr, ifg_time);

    ifg_time += ETHERNET_IFS_AS_REF_CLOCK_COUNT;
    ifg_time += (buf->length & 0x3) * 8;

    if (mii_get_and_dec_transmit_count(buf) == 0) {
      if (buf->timestamp_id && p_ts_queue) {
        buf->timestamp = time;
        mii_ts_queue_add_entry(*p_ts_queue, buf);
        buf->stage = MII_STAGE_SENT;
      }
      else {
        mii_free(buf);
      }
    }
  }
}

