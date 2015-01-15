#ifndef __RGMII_BUFFERING_H__
#define __RGMII_BUFFERING_H__

#include <xccompat.h>
#include <stdint.h>
#include "rgmii.h"
#include "ethernet.h"

// Support max sized frames with VLAN tag.
// Add an extra words to contain the packet size and timestamp.
#define MAX_ETH_FRAME_SIZE (ETHERNET_MAX_PACKET_SIZE + 8)

// Round up to the next full word
#define MAX_ETH_FRAME_SIZE_WORDS ((MAX_ETH_FRAME_SIZE + 3) / 4)

// Provide enough buffers to receive all minumum sized frames after
// a maximum sized frame - using a power of 2 value is more efficient
#define RGMII_MAC_BUFFER_COUNT 32

typedef struct buffers_free_t {
  unsigned top_index;
  uintptr_t stack[RGMII_MAC_BUFFER_COUNT];
} buffers_free_t;

void buffers_free_initialise(REFERENCE_PARAM(buffers_free_t, free), unsigned char *buffer);

typedef struct buffers_used_t {
  unsigned tail_index;
  unsigned head_index;
  uintptr_t pointers[RGMII_MAC_BUFFER_COUNT + 1];
} buffers_used_t;

void buffers_used_initialise(REFERENCE_PARAM(buffers_used_t, used));

void empty_channel(streaming_chanend_t c);

#ifdef __XC__
unsigned int buffer_manager_1000(streaming chanend c_rx0,
                                 streaming chanend c_rx1,
                                 streaming chanend c_tx,
                                 streaming chanend c_speed_change,
                                 out port p_txclk_out,
                                 in buffered port:4 p_rxd_interframe,
                                 buffers_used_t &used_buffers,
                                 buffers_free_t &free_buffers,
                                 rgmii_inband_status_t current_mode);

unsigned int buffer_manager_10_100(streaming chanend c_rx,
                                   streaming chanend c_tx,
                                   streaming chanend c_speed_change,
                                   out port p_txclk_out,
                                   in buffered port:4 p_rxd_interframe,
                                   buffers_used_t &used_buffers,
                                   buffers_free_t &free_buffers,
                                   rgmii_inband_status_t current_mode);

#endif

#endif // __RGMII_BUFFERING_H__
