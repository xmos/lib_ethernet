#include <platform.h>
#include "rgmii_buffering.h"
#include "rgmii_common.h"

extern "C" {
    extern void buffers_free_initialise_c(buffers_free_t *free, unsigned char *buffer);
}

void buffers_free_initialise(buffers_free_t &free, unsigned char *buffer)
{
  free.top_index = RGMII_MAC_BUFFER_COUNT;

  buffers_free_initialise_c(&free, buffer);
  for (unsigned i = 1; i < RGMII_MAC_BUFFER_COUNT; i++)
    free.stack[i] = free.stack[i - 1] + (MAX_ETH_FRAME_SIZE_WORDS * 4);
}

void buffers_used_initialise(buffers_used_t &used)
{
  used.head_index = 0;
  used.tail_index = 0;
}

#pragma unsafe arrays
static inline uintptr_t buffers_free_acquire(buffers_free_t &free)
{
  free.top_index--;
  uintptr_t buffer = free.stack[free.top_index];
  return buffer;
}

#pragma unsafe arrays
static inline void buffers_free_release(buffers_free_t &free, uintptr_t buffer)
{
  free.stack[free.top_index] = buffer;
  free.top_index++;
}

#pragma unsafe arrays
static inline void buffers_used_add(buffers_used_t &used, uintptr_t buffer)
{
  unsigned index = used.head_index % RGMII_MAC_BUFFER_COUNT;
  used.pointers[index] = buffer;
  used.head_index++;
}

#pragma unsafe arrays
static inline uintptr_t buffers_used_take(buffers_used_t &used)
{
  unsigned index = used.tail_index % RGMII_MAC_BUFFER_COUNT;
  used.tail_index++;
  return used.pointers[index];
}

void empty_channel(streaming chanend c)
{
  // Remove all data from the channels. Assumes data will all be words.
  timer t;
  unsigned time;
  t :> time;

  int done = 0;
  unsigned tmp;
  while (!done) {
    select {
      case c :> tmp:
        // Re-read the current time so that the timeout is from last data received
        t :> time;
        break;
      case t when timerafter(time + 100) :> void:
        done = 1;
        break;
    }
  }
}

unsigned int buffer_manager_1000(streaming chanend c_rx0,
                                 streaming chanend c_rx1,
                                 streaming chanend c_tx,
                                 streaming chanend c_speed_change,
                                 out port p_txclk_out,
                                 in buffered port:4 p_rxd_interframe,
                                 buffers_used_t &used_buffers,
                                 buffers_free_t &free_buffers,
                                 rgmii_inband_status_t current_mode)
{
  set_core_fast_mode_on();

  set_port_inv(p_txclk_out);

  // Start by issuing buffers to both of the miis
  c_rx0 <: buffers_free_acquire(free_buffers);
  c_rx1 <: buffers_free_acquire(free_buffers);

  // Give a second buffer to ensure no delay between packets
  c_rx0 <: buffers_free_acquire(free_buffers);
  c_rx1 <: buffers_free_acquire(free_buffers);

  // Signal to the testbench that the device is ready
  enable_rgmii(RGMII_DELAY, RGMII_DIVIDE_1G); 

  // Ensure that interrupts will be generated on this core
  install_speed_change_handler(p_rxd_interframe, current_mode);

  int sender_count = 0;
  int work_pending = 0;
  int done = 0;
  while (!done) {
    select {
      case c_rx0 :> uintptr_t buffer : {
        buffers_used_add(used_buffers, buffer);
        work_pending++;

        if (free_buffers.top_index == 0) {
          return 1;
        } else {
          c_rx0 <: buffers_free_acquire(free_buffers);
        }
        break;
      }

      case c_rx1 :> uintptr_t buffer : {
        buffers_used_add(used_buffers, buffer);
        work_pending++;

        if (free_buffers.top_index == 0) {
          return 1;
        } else {
          c_rx1 <: buffers_free_acquire(free_buffers);
        }
        break;
      }

      case c_tx :> uintptr_t sent_buffer : {
        sender_count--;
        buffers_free_release(free_buffers, sent_buffer);
        break;
      }

      work_pending && (sender_count < 2) => default : {
        // Send a pointer out to the outputter
        uintptr_t buffer = buffers_used_take(used_buffers);
        c_tx <: buffer;
        work_pending--;
        sender_count++;
        break;
      }

      case c_speed_change :> unsigned tmp : {
        done = 1;
        break;
      }
    }
  }

  // Clean up before changing speed
  empty_channel(c_rx0);
  empty_channel(c_rx1);
  empty_channel(c_tx);
  return 0;
}

unsigned int buffer_manager_10_100(streaming chanend c_rx,
                                   streaming chanend c_tx,
                                   streaming chanend c_speed_change,
                                   out port p_txclk_out,
                                   in buffered port:4 p_rxd_interframe,
                                   buffers_used_t &used_buffers,
                                   buffers_free_t &free_buffers,
                                   rgmii_inband_status_t current_mode)
{
  set_core_fast_mode_on();

  set_port_no_inv(p_txclk_out);

  // Start by issuing buffers to the receiver
  c_rx <: buffers_free_acquire(free_buffers);

  // Give a second buffer to ensure no delay between packets
  c_rx <: buffers_free_acquire(free_buffers);

  // Signal to the testbench that the device is ready
  enable_rgmii(RGMII_DELAY_100M, RGMII_DIVIDE_100M); 

  // Ensure that interrupts will be generated on this core
  install_speed_change_handler(p_rxd_interframe, current_mode);

  int sender_count = 0;
  int work_pending = 0;
  int done = 0;
  while (!done) {
    select {
      case c_rx :> uintptr_t buffer : {
        buffers_used_add(used_buffers, buffer);
        work_pending++;

        if (free_buffers.top_index == 0) {
          return 1;
        } else {
          c_rx <: buffers_free_acquire(free_buffers);
        }
        break;
      }

      case c_tx :> uintptr_t sent_buffer : {
        sender_count--;
        buffers_free_release(free_buffers, sent_buffer);
        break;
      }

      work_pending && (sender_count < 2) => default : {
        // Send a pointer out to the outputter
        uintptr_t buffer = buffers_used_take(used_buffers);
        c_tx <: buffer;
        work_pending--;
        sender_count++;
        break;
      }

      case c_speed_change :> unsigned tmp : {
        done = 1;
        break;
      }
    }
  }

  // Clean up before changing speed
  empty_channel(c_rx);
  empty_channel(c_tx);
  return 0;
}