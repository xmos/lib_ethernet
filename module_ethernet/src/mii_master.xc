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
#include "mii_ethernet.h"
#include "mii_buffering.h"
#include "debug_print.h"
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

#define ETHERNET_IFS_AS_REF_CLOCK_COUNT  (96)   // 12 bytes

// Receive timing constraints
#if ETHERNET_ENABLE_FULL_TIMINGS
#pragma xta command "remove exclusion *"

#pragma xta command "add exclusion mii_rx_begin"
#pragma xta command "add exclusion mii_eof_case"
//#pragma xta command "add exclusion mii_wait_for_buffers"

// Start of frame to first word is 32 bits = 320ns
#pragma xta command "analyze endpoints mii_rx_sof mii_rx_first_word"
#pragma xta command "set required - 320 ns"

// Start of frame to first word is 32 bits = 320ns
#pragma xta command "analyze endpoints mii_rx_sof mii_rx_first_word"
#pragma xta command "set required - 320 ns"

#pragma xta command "analyze endpoints mii_rx_first_word mii_rx_second_word"
#pragma xta command "set required - 320 ns"

#pragma xta command "analyze endpoints mii_rx_second_word mii_rx_third_word"
#pragma xta command "set required - 320 ns"

#pragma xta command "analyze endpoints mii_rx_third_word mii_rx_ethertype_word"
#pragma xta command "set required - 320 ns"

#pragma xta command "analyze endpoints mii_rx_ethertype_word mii_rx_fifth_word"
#pragma xta command "set required - 320 ns"

//#pragma xta command "analyze endpoints mii_rx_fifth_word mii_rx_sixth_word"
//#pragma xta command "set required - 320 ns"

#pragma xta command "analyze endpoints mii_rx_fifth_word mii_rx_word"
#pragma xta command "set required - 320 ns"

//#pragma xta command "analyze endpoints mii_rx_sixth_word mii_rx_word"
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
//#pragma xta command "add exclusion mii_wait_for_buffers"
//#pragma xta command "add exclusion mii_no_available_buffers"
//#pragma xta command "add exclusion mii_rx_correct_priority_buffer_unavailable"
//#pragma xta command "add exclusion mii_rx_data_inner_loop"
#pragma xta command "analyze endpoints mii_rx_eof mii_rx_sof"
#pragma xta command "set required - 1560 ns"


#endif
// check the transmit interframe space.  It should ideally be quite close to 1560, which will
// allow the timer check to control the transmission rather than being instruction time bound

//#pragma xta command "remove exclusion *"
//#pragma xta command "add exclusion mii_tx_sof"
//#pragma xta command "add exclusion mii_tx_buffer_not_marked_for_transmission"
//#pragma xta command "add exclusion mii_tx_not_valid_to_transmit"

//#pragma xta command "analyze endpoints mii_tx_end mii_tx_start"
//#pragma xta command "set required - 1560 ns"


void mii_master_init(mii_ports_t &m)
{
  set_port_use_on(m.p_rxclk);
  m.p_rxclk :> int x;
  set_port_use_on(m.p_rxd);
  set_port_use_on(m.p_rxdv);
  set_port_use_on(m.p_rxer);

  set_pad_delay(m.p_rxclk, PAD_DELAY_RECEIVE);

  set_port_strobed(m.p_rxd);
  set_port_slave(m.p_rxd);

  set_clock_on(m.clk_rx);
  set_clock_src(m.clk_rx, m.p_rxclk);
  set_clock_ready_src(m.clk_rx, m.p_rxdv);
  set_port_clock(m.p_rxd, m.clk_rx);
  set_port_clock(m.p_rxdv, m.clk_rx);

  set_clock_rise_delay(m.clk_rx, CLK_DELAY_RECEIVE);

  start_clock(m.clk_rx);

  clearbuf(m.p_rxd);

  set_port_use_on(m.p_txclk);
  set_port_use_on(m.p_txd);
  set_port_use_on(m.p_txen);
  //  set_port_use_on(m.p_txer);

  set_pad_delay(m.p_txclk, PAD_DELAY_TRANSMIT);

  m.p_txd <: 0;
  m.p_txen <: 0;
  //  m.p_txer <: 0;
  sync(m.p_txd);
  sync(m.p_txen);
  //  sync(m.p_txer);

  set_port_strobed(m.p_txd);
  set_port_master(m.p_txd);
  clearbuf(m.p_txd);

  set_port_ready_src(m.p_txen, m.p_txd);
  set_port_mode_ready(m.p_txen);

  set_clock_on(m.clk_tx);
  set_clock_src(m.clk_tx, m.p_txclk);
  set_port_clock(m.p_txd, m.clk_tx);
  set_port_clock(m.p_txen, m.clk_tx);

  set_clock_fall_delay(m.clk_tx, CLK_DELAY_TRANSMIT);

  start_clock(m.clk_tx);

  clearbuf(m.p_txd);
}

unsafe void mii_master_rx_pins(mii_mempool_t rxmem_hp,
                               mii_mempool_t rxmem_lp,
                               in port p_mii_rxdv,
                               in buffered port:32 p_mii_rxd,
                               streaming chanend c)
{
  timer tmr;
  unsigned * unsafe wrap_ptr;
  unsigned * unsafe wrap_ptr_hp;

  if (!ETHERNET_SUPPORT_HP_QUEUES)
    rxmem_hp = 0;

  /* Set up the wrap markers for the two memory buffers. These are the
     points at which we must wrap data back to the beginning of the buffer */
  wrap_ptr = mii_get_wrap_ptr(rxmem_lp);

  if (rxmem_hp)
    wrap_ptr_hp = mii_get_wrap_ptr(rxmem_hp);

  /* Make sure we do not start in the middle of a packet */
  p_mii_rxdv when pinseq(0) :> int lo;

  while (1) {
#pragma xta label "mii_rx_begin"
    unsigned word;
    mii_packet_t * unsafe buf, * unsafe buf_hp;
    unsigned * unsafe end_ptr, * unsafe end_ptr_hp;

    /* Grab buffers to read the packet into. mii_reserve always returns a
       buffer we can use (though it may be a dummy buffer that gets thrown
       away later if we are out of buffer space). */

    buf = mii_reserve(rxmem_lp, end_ptr);

    if (rxmem_hp)
      buf_hp = mii_reserve(rxmem_hp, end_ptr_hp);

    /* Wait for the start of the packet and timestamp it */
    #pragma xta endpoint "mii_rx_sof"
    p_mii_rxd when pinseq(0xD) :> int sof;

    #pragma xta endpoint "mii_rx_after_preamble"
    unsigned time;
    tmr :> time;

    unsigned crc = 0x9226F562;
    unsigned poly = 0xEDB88320;
    unsigned header[3];

    /* Read in the first four words of the packet into the header array.
       This gets copied into the packet buffer later */
    #pragma xta endpoint "mii_rx_first_word"
    p_mii_rxd :> header[0];
    crc32(crc, header[0], poly);

    #pragma xta endpoint "mii_rx_second_word"
    p_mii_rxd :> header[1];
    crc32(crc, header[1], poly);

    #pragma xta endpoint "mii_rx_third_word"
    p_mii_rxd :> header[2];
    crc32(crc, header[2], poly);

    #pragma xta endpoint "mii_rx_ethertype_word"
    p_mii_rxd :> word;
    crc32(crc, word, poly);

    /* Determine what buffer to use based on the ethertype field in
       the header */
    unsigned short etype = (unsigned short) word;
    if (rxmem_hp && etype == 0x0081) {
      buf = buf_hp;
      wrap_ptr = wrap_ptr_hp;
      end_ptr = end_ptr_hp;
    }

    buf->data[3] = word;
    unsigned * unsafe dptr = &buf->data[4];

    buf->timestamp = time;

    #pragma xta endpoint "mii_rx_fifth_word"
    p_mii_rxd :> word;
    crc32(crc, word, poly);
    *dptr++ = word;

    unsigned nbytes = 4*sizeof(word);
    unsigned endofframe;
    do
      {
#pragma xta label "mii_rx_data_inner_loop"
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
            nbytes+=4;
            endofframe = 0;
            break;
#pragma xta endpoint "mii_rx_eof"
          case p_mii_rxdv when pinseq(0) :> int lo:
            {
#pragma xta label "mii_eof_case"
              endofframe = 1;
              break;
            }
          }
      } while (!endofframe);

    unsigned tail;
    int taillen;
    taillen = endin(p_mii_rxd);
    buf->length = nbytes + (taillen>>3);

    unsigned mask = ~0U >> taillen;

    p_mii_rxd :> tail;

    /* Mask out junk bits in last input */
    tail &= ~mask;

    /* Incorporate tailbits of input data,
       see https://github.com/xcore/doc_tips_and_tricks for details. */
    { tail, crc } = mac(crc, mask, tail, crc);
    crc32(crc, tail, poly);

    buf->crc = crc;

    buf->data[0] = header[0];
    buf->data[1] = header[1];
    buf->data[2] = header[2];

    if (dptr != end_ptr) {
      /* We don't store the last word since it contains the CRC and
         we don't need it from this point on. */
      c <: buf;
      mii_commit(buf, dptr);
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

#pragma xta command "add exclusion mii_tx_final_partword_1"
#pragma xta command "analyze endpoints mii_tx_word mii_tx_crc_0"
#pragma xta command "set required - 320 ns"

#pragma xta command "remove exclusion mii_tx_final_partword_3"
#pragma xta command "remove exclusion mii_tx_final_partword_2"
#pragma xta command "remove exclusion mii_tx_final_partword_1"

#pragma xta command "analyze endpoints mii_tx_final_partword_3 mii_tx_final_partword_2"
#pragma xta command "set required - 80 ns"

#pragma xta command "analyze endpoints mii_tx_final_partword_2 mii_tx_final_partword_1"
#pragma xta command "set required - 80 ns"

#pragma xta command "analyze endpoints mii_tx_final_partword_1 mii_tx_crc_0"
#pragma xta command "set required - 80 ns"



#undef crc32
#define crc32(a, b, c) {__builtin_crc32(a, b, c);}

#ifndef MII_TX_TIMESTAMP_END_OF_PACKET
#define MII_TX_TIMESTAMP_END_OF_PACKET (0)
#endif

unsafe int mii_transmit_packet(mii_packet_t * unsafe buf,
                               out buffered port:32 p_mii_txd)
{
  timer tmr;
  int time;
  register const unsigned poly = 0xEDB88320;
  unsigned int crc = 0;
  unsigned * unsafe dptr;
  int i=0;
  int word_count = buf->length >> 2;
  int tail_byte_count = buf->length & 3;
  unsigned * unsafe wrap_ptr;
  dptr = &buf->data[0];
  wrap_ptr = mii_packet_get_wrap_ptr(buf);

#pragma xta endpoint "mii_tx_sof"
  p_mii_txd <: 0x55555555;
  p_mii_txd <: 0xD5555555;

  if (!MII_TX_TIMESTAMP_END_OF_PACKET && buf->timestamp_id) {
    int time;
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
#pragma xta endpoint "mii_tx_crc_0"
  p_mii_txd <: crc;
  return time;
}


unsafe void mii_master_tx_pins(mii_mempool_t hp_queue,
                               mii_mempool_t lp_queue,
                               mii_ts_queue_t ts_queue,
                               out buffered port:32 p_mii_txd,
                               int enable_shaper,
                               volatile int * unsafe idle_slope)
{
  int credit = 0;
  int credit_time;
  int prev_eof_time, time;
  timer tmr;
  int ok_to_transmit=1;

  if (!ETHERNET_SUPPORT_HP_QUEUES)
    hp_queue = 0;

  if (!ETHERNET_SUPPORT_TRAFFIC_SHAPER)
    enable_shaper = 0;

  if (hp_queue && enable_shaper)
    tmr :> credit_time;

  while (1) {
#pragma xta label "mii_tx_main_loop"
    mii_packet_t * unsafe buf = null;
    int bytes_left;

    int stage;
    int prev_credit_time;
    int elapsed;

    if (hp_queue)
      buf = mii_get_next_buf(hp_queue);

    if (enable_shaper) {
      if (buf && buf->stage == 1) {

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

    if (!hp_queue || !buf || buf->stage != 1)
      buf = mii_get_next_buf(lp_queue);


    // Check that we are out of the IFS period
    tmr :> time;
    if (((int) time - (int) prev_eof_time) >= ETHERNET_IFS_AS_REF_CLOCK_COUNT) {
      ok_to_transmit = 1;
    }

    if (!buf || !ok_to_transmit) {
#pragma xta endpoint "mii_tx_not_valid_to_transmit"
      continue;
    }

    if (buf->stage != 1) {
#pragma xta endpoint "mii_tx_buffer_not_marked_for_transmission"
      continue;
    }

#pragma xta endpoint "mii_tx_start"
    time = mii_transmit_packet(buf, p_mii_txd);
#pragma xta endpoint "mii_tx_end"

    tmr :> prev_eof_time;
    ok_to_transmit = 0;

    if (mii_get_and_dec_transmit_count(buf) == 0) {
      if (buf->timestamp_id) {
        buf->timestamp = time;
        mii_ts_queue_add_entry(ts_queue, buf);
        buf->stage = 2;
      }
      else {
        mii_free(buf);
      }
    }
  }
}



