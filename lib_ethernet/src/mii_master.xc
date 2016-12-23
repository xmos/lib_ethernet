// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#include "mii_master.h"
#include <xs1.h>
#include <print.h>
#include <stdlib.h>
#include <syscall.h>
#include <xclib.h>
#include <hwtimer.h>
#include "mii_buffering.h"
#include "debug_print.h"
#include "default_ethernet_conf.h"
#include "mii_common_lld.h"
#include "string.h"

#define QUOTEAUX(x) #x
#define QUOTE(x) QUOTEAUX(x)

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
#define MII_ETHERNET_IFS_AS_REF_CLOCK_COUNT  (96 + 96 - 9)

// Receive timing constraints
#if ETHERNET_ENABLE_FULL_TIMINGS && defined(__XS1B__)
#pragma xta command "config Terror on"
#pragma xta command "remove exclusion *"

#pragma xta command "add exclusion mii_rx_begin"
#pragma xta command "add exclusion mii_eof_case"
//#pragma xta command "add exclusion mii_wait_for_buffers"

// Start of frame to first word is 32 bits = 320ns
// But the buffers can hold two words so it can take a bit longer
#pragma xta command "analyze endpoints mii_rx_sof mii_rx_word"
#pragma xta command "set required - 380 ns"

// Word reception timing
#pragma xta command "analyze endpoints mii_rx_word mii_rx_word"
#pragma xta command "set required - 320 ns"

// The end of frame timing is 12 octets IFS + 7 octets preamble + 1 nibble preamble = 156 bits - 1560ns
// However, in the case where there is one byte in the buffer as the last word is processed then
// there is actually only 1360ns available for that path.
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
#pragma xta command "analyze endpoints mii_rx_eof mii_rx_sof"
#pragma xta command "set required - 1360 ns"

#pragma xta command "add exclusion mii_rx_no_tail"
#pragma xta command "analyze endpoints mii_rx_eof mii_rx_sof"
#pragma xta command "set required - 1240 ns"

#endif
// check the transmit interframe space.  It should ideally be quite close to 1560, which will
// allow the timer check to control the transmission rather than being instruction time bound

//#pragma xta command "remove exclusion *"
//#pragma xta command "add exclusion mii_tx_sof"
//#pragma xta command "add exclusion mii_tx_not_valid_to_transmit"

//#pragma xta command "analyze endpoints mii_tx_end mii_tx_start"
//#pragma xta command "set required - 1560 ns"

void mii_master_init(in port p_rxclk, in buffered port:32 p_rxd, in port p_rxdv,
                     clock clk_rx,
                     in port p_txclk, out port p_txen, out buffered port:32 p_txd,
                     clock clk_tx, in buffered port:1 p_rxer)
{
  set_port_use_on(p_rxclk);
  p_rxclk :> int x;
  set_port_use_on(p_rxd);
  set_port_use_on(p_rxdv);

  set_pad_delay(p_rxclk, PAD_DELAY_RECEIVE);

  set_port_strobed(p_rxd);
  set_port_slave(p_rxd);

  configure_in_port_strobed_slave(p_rxer, p_rxdv, clk_rx);

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

unsafe void mii_master_rx_pins(mii_mempool_t rx_mem,
                               mii_packet_queue_t incoming_packets,
                               unsigned * unsafe rdptr,
                               in port p_mii_rxdv,
                               in buffered port:32 p_mii_rxd,
                               in buffered port:1 p_mii_rxer,
                               streaming chanend c)
{
  timer tmr;

  unsigned kernel_stack[MII_COMMON_HANDLER_STACK_WORDS];
  /* Pointers to data that needs the latest value being read */
  volatile unsigned * unsafe error_ptr = mii_setup_error_port(p_mii_rxer, p_mii_rxdv, kernel_stack);
  volatile unsigned * unsafe p_rdptr = (volatile unsigned * unsafe)rdptr;

  /* Set up the wrap markers for the two memory buffers. These are the
     points at which we must wrap data back to the beginning of the buffer */
  unsigned * unsafe wrap_ptr = mii_get_wrap_ptr(rx_mem);

  /* Make sure we do not start in the middle of a packet */
  p_mii_rxdv when pinseq(0) :> int lo;

  while (1) {

    /* Discount the CRC word */
    int num_rx_bytes = -4;

    /* Read the shared pointer where the read pointer is kept up to date
     * by the management process (mii_ethernet_server_aux). */
    unsigned * unsafe rdptr = (unsigned * unsafe)*p_rdptr;

    /* Grab buffers to read the packet into. mii_reserve always returns a
     * buffer we can use (though it may be a dummy buffer that gets thrown
     * away later if we are out of buffer space). */
    unsigned * unsafe end_ptr;
    mii_packet_t * unsafe buf = mii_reserve(rx_mem, rdptr, &end_ptr);

    unsigned crc = 0x9226F562;
    unsigned poly = 0xEDB88320;
    unsigned * unsafe dptr = &buf->data[0];

    /* Enable interrupts as the rx_err port is configured to raise an interrupt
     * that logs the error and continues. */
    asm("setsr 0x2");

    /* Wait for the start of the packet and timestamp it */
    unsigned sfd_preamble;
    #pragma xta endpoint "mii_rx_sof"
    p_mii_rxd when pinseq(0xD) :> sfd_preamble;

    if (((sfd_preamble >> 24) & 0xFF) != 0xD5) {
      /* Corrupt the CRC so that the packet is discarded */
      crc = ~crc;
    }

    /* Timestamp the start of packet and record it in the packet structure */
    #pragma xta endpoint "mii_rx_after_preamble"
    unsigned time;
    tmr :> time;
    buf->timestamp = time;

    unsigned end_of_frame = 0;
    unsigned word;

    do {
     select
       {
#pragma xta endpoint "mii_rx_word"
       case p_mii_rxd :> word:
         *dptr = word;
         crc32(crc, word, poly);

         /* Prevent the overwriting of packets in the buffer. If the end_ptr is reached
          * then this packet will be dropped as there is not enough room in the buffer. */
         if (dptr != end_ptr) {
           dptr++;
           /* The wrap pointer contains the address of the start of the buffer */
           if (dptr == wrap_ptr)
             dptr = (unsigned * unsafe) *dptr;
         }

         num_rx_bytes += 4;
         break;

#pragma xta endpoint "mii_rx_eof"
       case p_mii_rxdv when pinseq(0) :> int:
#pragma xta label "mii_eof_case"
         end_of_frame = 1;
         break;
      }
    } while (!end_of_frame);

    /* Clear interrupts used by rx_err port handler */
    asm("clrsr 0x2");

    /* If the rx_err port detects an error then drop the packet */
    if (*error_ptr) {
      endin(p_mii_rxd);
      p_mii_rxd :> void;
      *error_ptr = 0;
      continue;
    }

    /* Note: we don't store the last word since it contains the CRC and
     * we don't need it from this point on. */

#pragma xta label "mii_rx_begin"
    unsigned taillen = endin(p_mii_rxd);

    unsigned tail;
    p_mii_rxd :> tail;

    if (taillen & ~0x7) {
      #pragma xta label "mii_rx_no_tail"

      num_rx_bytes += (taillen>>3);

      /* Ensure that the mask is byte-aligned */
      unsigned mask = ~0U >> (taillen & ~0x7);

      /* Correct for non byte-aligned frames */
      tail <<= taillen & 0x7;

      /* Mask out junk bits in last input */
      tail &= ~mask;

      /* Incorporate tailbits of input data,
       * see https://github.com/xcore/doc_tips_and_tricks for details. */
      { tail, crc } = mac(crc, mask, tail, crc);
      crc32(crc, tail, poly);
    }

    buf->length = num_rx_bytes;
    buf->crc = crc;

    if (dptr != end_ptr) {
      /* Update where the write pointer is in memory */
      mii_commit(rx_mem, dptr);

      /* Record the fact that there is a valid packet ready for filtering
       *  - the assumption is that the filtering is running fast enough
       *    to keep up and process the packets so that the incoming_packet
       *    pointers never fill up
       */
      mii_add_packet(incoming_packets, buf);
    }
  }

  return;
}


////////////////////////////////// TRANSMIT ////////////////////////////////

// Transmit timing constraints
#ifdef __XS1B__
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
#endif


#undef crc32
#define crc32(a, b, c) {__builtin_crc32(a, b, c);}

#ifndef MII_TX_TIMESTAMP_END_OF_PACKET
#define MII_TX_TIMESTAMP_END_OF_PACKET (0)
#endif

unsafe unsigned mii_transmit_packet(mii_mempool_t tx_mem,
                                    mii_packet_t * unsafe buf,
                                    out buffered port:32 p_mii_txd,
                                    hwtimer_t ifg_tmr, unsigned &ifg_time)
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
  wrap_ptr = mii_get_wrap_ptr(tx_mem);

  // Check that we are out of the inter-frame gap
#pragma xta endpoint "mii_tx_start"
  asm volatile ("in %0, res[%1]"
                  : "=r" (ifg_time)
                  : "r" (ifg_tmr));

#pragma xta endpoint "mii_tx_sof"
  p_mii_txd <: 0x55555555;
  p_mii_txd <: 0xD5555555;

  if (!MII_TX_TIMESTAMP_END_OF_PACKET && buf->timestamp_id) {
    ifg_tmr :> time;
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
    ifg_tmr :> ifg_time;
  } while (i < word_count);

  if (MII_TX_TIMESTAMP_END_OF_PACKET && buf->timestamp_id) {
    ifg_tmr :> time;
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


unsafe void mii_master_tx_pins(mii_mempool_t tx_mem_lp,
                               mii_mempool_t tx_mem_hp,
                               mii_packet_queue_t packets_lp,
                               mii_packet_queue_t packets_hp,
                               mii_ts_queue_t ts_queue,
                               out buffered port:32 p_mii_txd,
                               volatile ethernet_port_state_t * unsafe p_port_state)
{
  int credit = 0;
  int credit_time;
  // Need one timer to be able to read at any time for the shaper
  timer credit_tmr;
  // And a second timer to be enforcing the IFG gap
  hwtimer_t ifg_tmr;
  unsigned ifg_time;
  unsigned enable_shaper = p_port_state->qav_shaper_enabled;

  if (!ETHERNET_SUPPORT_TRAFFIC_SHAPER)
    enable_shaper = 0;

  if (ETHERNET_SUPPORT_HP_QUEUES && enable_shaper) {
    credit_tmr :> credit_time;
  }

  ifg_tmr :> ifg_time;

  while (1) {
#pragma xta label "mii_tx_main_loop"
    mii_packet_t * unsafe buf = null;
    mii_ts_queue_t *p_ts_queue = null;
    mii_mempool_t tx_mem = tx_mem_hp;

    if (ETHERNET_SUPPORT_HP_QUEUES)
      buf = mii_get_next_buf(packets_hp);

    if (enable_shaper) {
      int prev_credit_time = credit_time;
      credit_tmr :> credit_time;

      int elapsed = credit_time - prev_credit_time;
      credit += elapsed * p_port_state->qav_idle_slope;

      if (buf) {
        if (credit < 0) {
          buf = 0;
        }
      }
      else {
        if (credit > 0)
          credit = 0;
      }
    }

    if (!buf) {
      buf = mii_get_next_buf(packets_lp);
      p_ts_queue = &ts_queue;
      tx_mem = tx_mem_lp;
    }

    if (!buf) {
#pragma xta endpoint "mii_tx_not_valid_to_transmit"
      continue;
    }

    unsigned time = mii_transmit_packet(tx_mem, buf, p_mii_txd, ifg_tmr, ifg_time);

    // Setup the hardware timer to enforce the IFG
    ifg_time += MII_ETHERNET_IFS_AS_REF_CLOCK_COUNT;
    ifg_time += (buf->length & 0x3) * 8;
    asm volatile ("setd res[%0], %1"
                    : // No dests
                    : "r" (ifg_tmr), "r" (ifg_time));
    asm volatile ("setc res[%0], " QUOTE(XS1_SETC_COND_AFTER)
                    : // No dests
                    : "r" (ifg_tmr));

    const int packet_is_high_priority = (p_ts_queue == null);
    if (enable_shaper && packet_is_high_priority) {
      const int preamble_bytes = 8;
      const int ifg_bytes = 96/8;
      const int crc_bytes = 4;
      int len = buf->length + preamble_bytes + ifg_bytes + crc_bytes;
      credit = credit - (len << (MII_CREDIT_FRACTIONAL_BITS+3));
    }

    if (mii_get_and_dec_transmit_count(buf) == 0) {

      /* The timestamp queue is only set for low-priority packets */
      if (!packet_is_high_priority) {
        if (buf->timestamp_id) {
          mii_ts_queue_add_entry(*p_ts_queue, buf->timestamp_id, time);
        }

        mii_free_current(packets_lp);
      }
      else {
        mii_free_current(packets_hp);
      }
    }
  }
}

