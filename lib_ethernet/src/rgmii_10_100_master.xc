// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <xclib.h>
#include <platform.h>
#include <stdint.h>
#include "ethernet.h"
#include "rgmii_10_100_master.h"
#include "rgmii_consts.h"
#include "rgmii.h"
#include "mii_common_lld.h"
#include "mii_buffering.h"
#include "ntoh.h"

#ifndef ETHERNET_ENABLE_FULL_TIMINGS
#define ETHERNET_ENABLE_FULL_TIMINGS (1)
#endif

// Receive timing constraints
#if ETHERNET_ENABLE_FULL_TIMINGS && defined(__XS1B__)
#pragma xta command "config Terror on"
#pragma xta command "remove exclusion *"

#pragma xta command "add exclusion rgmii_10_100_rx_begin"
#pragma xta command "add exclusion rgmii_10_100_eof_case"

// Start of frame to first word is 32 bits = 320ns
#pragma xta command "analyze endpoints rgmii_10_100_rx_sof rgmii_10_100_rx_word"
#pragma xta command "set required - 320 ns"

#pragma xta command "analyze endpoints rgmii_10_100_rx_word rgmii_10_100_rx_word"
#pragma xta command "set required - 300 ns"

// The end of frame timing is 12 octets IFS + 7 octets preamble + 1 nibble preamble = 156 bits - 1560ns
//
// note: the RXDV will come low with the start of the pre-amble, but the code
//       checks for a valid RXDV and then starts hunting for the 'D' nibble at
//       the end of the pre-amble, so we don't need to spot the rising edge of
//       the RXDV, only the point where RXDV is valid and there is a 'D' on the
//       data lines.
#pragma xta command "remove exclusion *"
#pragma xta command "add exclusion rgmii_10_100_rx_after_preamble"
#pragma xta command "add exclusion rgmii_10_100_rx_eof"
#pragma xta command "add exclusion rgmii_10_100_rx_word"
#pragma xta command "analyze endpoints rgmii_10_100_rx_eof rgmii_10_100_rx_sof"
#pragma xta command "set required - 1560 ns"

#endif

unsafe void rgmii_10_100_master_rx_pins(streaming chanend c,
                                 in buffered port:32 p_rxd_10_100,
                                 in port p_rxdv,
                                 in buffered port:1 p_rxer,
                                 streaming chanend c_speed_change)
{
  timer tmr;

  // Convert the RXDV ports back to generating events as the gigabit implementation
  // uses interrupts
  asm("setc res[%0], %1" : /* no output */ : "r"(p_rxdv), "r"(XS1_SETC_IE_MODE_EVENT));

  unsigned kernel_stack[MII_COMMON_HANDLER_STACK_WORDS];
  volatile unsigned * unsafe error_ptr = mii_setup_error_port(p_rxer, p_rxdv, kernel_stack);

  while (1) {
#pragma xta label "rgmii_10_100_rx_begin"
    uintptr_t buffer;
    unsigned timestamp;
    unsigned num_packet_bytes;

    select {
      case c_speed_change :> buffer:
        return;
      case c :> buffer:
        break;
    }

    mii_packet_t * unsafe buf = (mii_packet_t * unsafe)buffer;

    while (1) {
      register const unsigned poly = 0xEDB88320;

      unsafe {
        // Pre-load CRC with value making equivalent of doing crc of ~first_word
        unsigned int crc = 0x9226F562;
        unsigned int word;
        unsigned * unsafe dptr = buf->data;

        // Enable interrupts
        asm("setsr 0x2");

        unsigned sfd_preamble;
        select {
          case c_speed_change :> buffer:
            // Disable interrupts
            asm("clrsr 0x2");
            return;
#pragma xta endpoint "rgmii_10_100_rx_sof"
          case p_rxd_10_100 when pinseq(0xD) :> sfd_preamble:
            break;
        }

        // Timestamp the start of packet
#pragma xta endpoint "rgmii_10_100_rx_after_preamble"
        unsigned time;
        tmr :> time;
        buf->timestamp = time;

        int i = 0;
        int done = 0;
        int err = 0;

        while (!done)
        {
          select {
#pragma xta endpoint "rgmii_10_100_rx_word"
            case p_rxd_10_100 :> word:
              // Don't write beyond the end of the buffer
              if (i < ETHERNET_MAX_PACKET_SIZE)
                  dptr[0] = word;
              crc32(crc, word, poly);
              i += 4;
              dptr += 1;
              break;

#pragma xta endpoint "rgmii_10_100_rx_eof"
            case p_rxdv when pinseq(0) :> int lo:
            {
#pragma xta label "rgmii_10_100_eof_case"
              done = 1;

              unsigned tail;
              int taillen = endin(p_rxd_10_100);
              p_rxd_10_100 :> tail;
              tail = tail >> (32 - taillen);

              int tail_byte_count = (taillen >> 3);
              num_packet_bytes = i + tail_byte_count;

              // Discount the CRC
              num_packet_bytes -= 4;

              if (num_packet_bytes < 60 || num_packet_bytes > ETHERNET_MAX_PACKET_SIZE)
              {
                err = 1;
                break;
              }

              // Store the byte count in the packet structure
              buf->length = num_packet_bytes;

              if (tail_byte_count)
              {
                switch (tail_byte_count)
                {
                  default:
                    __builtin_unreachable();
                    break;
                  #pragma fallthrough
                  case 3:
                    tail = crc8shr(crc, tail, poly);
                  #pragma fallthrough
                  case 2:
                    tail = crc8shr(crc, tail, poly);
                  case 1:
                    crc8shr(crc, tail, poly);
                    break;
                }
              }

              if (~crc)
                err = 1;

              break;
            }
          }
        }

        // Clear interrupts
        asm("clrsr 0x2");

        if ((((sfd_preamble >> 24) & 0xFF) != 0xD5) ||
            *error_ptr)
        {
          endin(p_rxd_10_100);
          p_rxd_10_100 :> void;
          *error_ptr = 0;
          continue;
        }

        // Check that the len/type field specifies a valid length (same or
        // less than the amount of data received).
        int *unsafe p_len_type = (int *unsafe) &((int *)buffer)[MII_PACKET_HEADER_WORDS + 3];
        uint16_t len_type = (uint16_t) NTOH_U16_ALIGNED(p_len_type);
        unsigned header_len = 14;
        if (len_type == 0x8100) {
          header_len += 4;
          p_len_type = (int *unsafe) &((int *)buffer)[MII_PACKET_HEADER_WORDS + 4];
          len_type = (uint16_t) NTOH_U16_ALIGNED(p_len_type);
        }
        const unsigned num_data_bytes = num_packet_bytes - header_len;

        if ((len_type < 1536) && (len_type > num_data_bytes))
          err = 1;

        if (!err)
        {
          // Packet sent, return buffer to manager
          c <: buffer;
          break;
        }
      } // unsafe
    } // while (1) until valid packet received
  } // while (1) until speed change
}

{unsigned, unsigned} zip2(unsigned a, unsigned b)
{
#if defined(__XS2A__)
  unsigned tmp1;
  unsigned tmp2;
  asm("mov %0, %2;"
      "mov %1, %3;"
      "zip %0, %1, 2" : "=&r"(tmp1), "=&r"(tmp2) : "r"(a), "r"(b));
  return {tmp1, tmp2};
#else
  __builtin_trap();
  return {0, 0};
#endif
}

unsafe void rgmii_10_100_master_tx_pins(streaming chanend c,
                                 out buffered port:32 p_txd,
                                 streaming chanend c_speed_change)
{
  unsigned tmp1, tmp2;
  timer tmr;
  unsigned ifg_time;
  tmr :> ifg_time;

  while (1)
  {
    uintptr_t buffer;
    unsigned timestamp;
    select
    {
      case c_speed_change :> buffer:
        return;
      case c :> buffer:
        break;
    }

    unsigned int eof_time;
    int tail_byte_count;

    mii_packet_t * unsafe buf = (mii_packet_t * unsafe)buffer;

    unsafe {
      register const unsigned poly = 0xEDB88320;
      // Pre-load CRC with value making equivalent of doing crc of ~first_word
      unsigned int crc = 0x9226F562;
      unsigned int word;
      unsigned * unsafe dptr = buf->data;
      int byte_count = buf->length;
      int word_count = byte_count >> 2;
      tail_byte_count = byte_count & 3;

      // Ensure that the interframe gap is respected
      tmr when timerafter(ifg_time) :> ifg_time;

      // Send the preamble
      {tmp1, tmp2} = zip2(0x55555555, 0x55555555);
      p_txd <: tmp2;
      p_txd <: tmp1;
      {tmp1, tmp2} = zip2(0xD5555555, 0xD5555555);
      p_txd <: tmp2;
      p_txd <: tmp1;

      // Timestamp the start of the packet
      unsigned int time;
      tmr :> time;
      buf->timestamp = time;

      int i = 0;
      do {
        word = dptr[0];
        dptr += 1;
        i++;
        crc32(crc, word, poly);
        {tmp1, tmp2} = zip2(word, word);
        p_txd <: tmp2;
        p_txd <: tmp1;
        tmr :> eof_time;
      } while (i < word_count);

      if (tail_byte_count)
      {
        word = dptr[0];
        {tmp1, tmp2} = zip2(word, word);
        switch (tail_byte_count)
        {
          case 3:
            p_txd <: tmp2;
            word = crc8shr(crc, word, poly);
            word = crc8shr(crc, word, poly);
            word = crc8shr(crc, word, poly);
            partout(p_txd, 16, tmp1);
            break;
          case 2:
            p_txd <: tmp2;
            word = crc8shr(crc, word, poly);
            word = crc8shr(crc, word, poly);
            break;
          case 1:
            partout(p_txd, 16, tmp2);
            crc8shr(crc, word, poly);
            break;
          default:
            __builtin_unreachable();
            break;
        }
      }
      crc32(crc, ~0, poly);
      {tmp1, tmp2} = zip2(crc, crc);
      p_txd <: tmp2;
      p_txd <: tmp1;
    }

    // Packet sent, return buffer to manager
    c <: buffer;

    // Compute next valid packet start time
    ifg_time = eof_time + RGMII_ETHERNET_IFS_AS_REF_CLOCK_COUNT;
    ifg_time += tail_byte_count * 8;
  }
}
