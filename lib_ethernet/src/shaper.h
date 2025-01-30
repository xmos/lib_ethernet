// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __shaper_h__
#define __shaper_h__

#include <stdio.h>
#include "ethernet.h"
#include "server_state.h"
#include "mii_buffering.h"
#include "xassert.h"
#include <print.h>

#ifndef ETHERNET_SUPPORT_TRAFFIC_SHAPER_CREDIT_LIMIT
#define ETHERNET_SUPPORT_TRAFFIC_SHAPER_CREDIT_LIMIT 1
#endif

static const unsigned preamble_bytes = 8;
static const unsigned crc_bytes = 4;
static const unsigned ifg_bytes = 96 / 8;

/** Type which stores the Qav credit based shaper state */
typedef struct qav_state_t{
  int prev_time;    /**< Previous time in hw_timer ticks (10ns, 32b). */
  int current_time; /**< Current time in hw_timer ticks (10ns, 32b). */
  int credit;       /**< Credit in MII_CREDIT_FRACTIONAL_BITS fractional format. */
} qav_state_t;

/** Sets the Qav idle slope in units of bits per second.
 *
 *   \param port_state  Pointer to the port state to be modified
 *   \param limit_bps   The idle slope setting in bits per second
 *
 */
void set_qav_idle_slope(ethernet_port_state_t * port_state, unsigned limit_bps);


/** Sets the Qav credit limit in units of frame size byte
 *
 *   \param port_state    Pointer to the port state to be modified
 *   \param limit_bytes   The credit limit in units of payload size in bytes to set as a credit limit,
 *                        not including preamble, CRC and IFG. Set to 0 for no limit (default)
 *
 */
void set_qav_credit_limit(ethernet_port_state_t * port_state, int payload_limit_bytes);


/** Performs the idle slope calculation for MII and RMII MACs.
 * 
 * Adds credits based on time since last HP packet and bit rate. If credit after calculation is above zero then
 * the HP packet is allowed to be transmitted. If credit is negative then the return buffer
 * is null so that it waits until credit is sufficient. 
 * 
 * The credit is optionally limited to hiCredit which is initialised by set_qav_credit_limit()
 * 
 *   \param hp_buf        Pointer to packet to be transmitted
 *   \param qav_state     Pointer to Qav state struct
 *   \param port_state    Pointer to MAC port state
 * 
 *   \returns             The hp_buf passed to it which is either maintained if credit is sufficient
 *                        or NULL if credit is not sufficient.
 */
static inline mii_packet_t * unsafe shaper_do_idle_slope(mii_packet_t * unsafe hp_buf,
                                                         qav_state_t * unsafe qav_state,
                                                         ethernet_port_state_t * unsafe port_state){
  unsafe{
    uint32_t elapsed_ticks = qav_state->current_time - qav_state->prev_time;

#if ETHERNET_SUPPORT_TRAFFIC_SHAPER_CREDIT_LIMIT
    int64_t credit64 = (int64_t)elapsed_ticks * (int64_t)port_state->qav_idle_slope + (int64_t)qav_state->credit;
    // cast qav_credit_limit as saves a cycle
    if((unsigned)port_state->qav_credit_limit && (credit64 > port_state->qav_credit_limit))
    {
      qav_state->credit = port_state->qav_credit_limit;
      // printf("credit: %llu limit: %llu\n", credit64, port_state->qav_credit_limit);
    } else {
      qav_state->credit = (int)credit64;
    }
#else
    // This is the old code from <4.0.0
    qav_state->credit += elapsed_ticks * (int)port_state->qav_idle_slope; // add bit budget since last transmission to credit. ticks * bits/tick = bits
#endif

    // If valid hp buffer
    if (hp_buf) {
      if (qav_state->credit < 0) {
        hp_buf = 0; // if out of credit drop this HP packet
      }
    }
    else
    // Buffer invalid, no HP packet so reset credit as per Annex L of Qav
    {
      if (qav_state->credit > 0){
        qav_state->credit = 0; // HP ready to send next time
      }
    }

    // Ensure we keep track of state (time since last packet) for next time
    qav_state->prev_time = qav_state->current_time;

    return hp_buf;
  }
}


static inline void shaper_do_send_slope(int len_bytes, qav_state_t * unsafe qav_state){
  unsafe{
    // Calculate number of additional byte slots on wire over the payload
    const int overhead_bytes = preamble_bytes + crc_bytes + ifg_bytes;
    
    // decrease credit by no. of bits transmitted, scaled by MII_CREDIT_FRACTIONAL_BITS
    // Note we don't need to check for overflow here as we will only be here if credit
    // was previously positive (worst case 1) and len_bytes <= ETHERNET_MAX_PACKET_SIZE so
    // will only decrement by roughly -(1<<29)
    qav_state->credit = qav_state->credit - ((len_bytes + overhead_bytes) << (MII_CREDIT_FRACTIONAL_BITS + 3)); // MII_CREDIT_FRACTIONAL_BITS+3 to convert from bytes to bits
  }
}


#endif // __shaper_h__
