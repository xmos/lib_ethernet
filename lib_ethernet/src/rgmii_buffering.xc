#include <string.h>
#include <platform.h>
#include "rgmii_buffering.h"
#include "rgmii_common.h"
#define DEBUG_UNIT RGMII_CLIENT_HANDLER
#include "debug_print.h"
#include "print.h"
#include "xassert.h"

// Re-define as a select handler until changed in xs1.h
#pragma select handler
void sin_char_array(streaming chanend c, char src[size], unsigned size);


#if ETHERNET_USE_HARDWARE_LOCKS
hwlock_t rgmii_memory_lock = 0;
#endif

#ifndef ETHERNET_USE_HARDWARE_LOCKS
  #define LOCK(buffers) swlock_acquire((buffers)->lock)
#else
  #define LOCK(buffers) hwlock_acquire(ethernet_memory_lock)
#endif

#ifndef ETHERNET_USE_HARDWARE_LOCKS
  #define UNLOCK(buffers) swlock_release((buffers)->lock)
#else
  #define UNLOCK(buffers) hwlock_release(ethernet_memory_lock)
#endif

extern "C" {
  extern void buffers_free_initialize_c(buffers_free_t *free, unsigned char *buffer);
}

void rgmii_init_lock()
{
#if ETHERNET_USE_HARDWARE_LOCKS
  if (rgmii_memory_lock == 0) {
    rgmii_memory_lock = hwlock_alloc();
  }
#endif
}

void buffers_free_initialize(buffers_free_t &free, unsigned char *buffer)
{
  free.top_index = RGMII_MAC_BUFFER_COUNT;
  buffers_free_initialize_c(&free, buffer);
  for (unsigned i = 1; i < RGMII_MAC_BUFFER_COUNT; i++)
    free.stack[i] = free.stack[i - 1] + sizeof(mii_packet_t);

#if !ETHERNET_USE_HARDWARE_LOCKS
  swlock_init(&free->lock);
#endif
}

void buffers_used_initialize(buffers_used_t &used)
{
  used.head_index = 0;
  used.tail_index = 0;

#if !ETHERNET_USE_HARDWARE_LOCKS
  swlock_init(&used->lock);
#endif
}

#pragma unsafe arrays
static unsafe inline mii_packet_t * unsafe buffers_free_take(buffers_free_t &free)
{
  LOCK(free);

  mii_packet_t * unsafe buf = NULL;

  // Ensure that the compiler does not keep this value in a register
  volatile unsigned * unsafe p_top_index = (volatile unsigned * unsafe)(&free.top_index);
  unsigned top_index = *p_top_index;

  if (top_index != 0) {
    top_index--;
    buf = (mii_packet_t *)free.stack[top_index];
    *p_top_index = top_index;
  }

  UNLOCK(free);
  return buf;
}

#pragma unsafe arrays
static unsafe inline void buffers_free_add(buffers_free_t &free, mii_packet_t * unsafe buf)
{
  LOCK(free);

  // Ensure that the compiler does not keep this value in a register
  volatile unsigned * unsafe p_top_index = (volatile unsigned * unsafe)(&free.top_index);
  unsigned top_index = *p_top_index;

  unsafe {
    free.stack[top_index] = (uintptr_t)buf;
  }
  top_index++;
  *p_top_index = top_index;

  UNLOCK(free);
}

#pragma unsafe arrays
static unsafe inline unsafe uintptr_t * unsafe buffers_used_add(buffers_used_t &used, mii_packet_t * unsafe buf)
{
  LOCK(used);

  // Ensure that the compiler does not keep this value in a register
  volatile unsigned * unsafe p_head_index = (volatile unsigned * unsafe)(&used.head_index);
  unsigned head_index = *p_head_index;

  unsigned index = head_index % RGMII_MAC_BUFFER_COUNT;
  used.pointers[index] = (uintptr_t)buf;
  head_index++;
  *p_head_index = head_index;

  UNLOCK(used);

  return &used.pointers[index];
}

#pragma unsafe arrays
static unsafe inline mii_packet_t * unsafe buffers_used_take(buffers_used_t &used)
{
  LOCK(used);

  // Ensure that the compiler does not keep this value in a register
  volatile unsigned * unsafe p_tail_index = (volatile unsigned * unsafe)(&used.tail_index);
  unsigned tail_index = *p_tail_index;

  unsigned index = tail_index % RGMII_MAC_BUFFER_COUNT;
  tail_index++;
  *p_tail_index = tail_index;

  unsafe {
    mii_packet_t * unsafe buf = (mii_packet_t *)used.pointers[index];

    UNLOCK(used);

    return buf;
  }
}

#pragma unsafe arrays
static inline mii_packet_t * unsafe buffers_used_head(buffers_used_t &used)
{
  unsigned index = used.tail_index % RGMII_MAC_BUFFER_COUNT;
  unsafe {
    return (mii_packet_t *)used.pointers[index];
  }
}

#pragma unsafe arrays
static unsafe inline int buffers_used_empty(buffers_used_t &used)
{
  // Ensure that the compiler does not keep this value in a register
  volatile unsigned * unsafe p_head_index = (volatile unsigned * unsafe)(&used.head_index);
  unsigned head_index = *p_head_index;
  volatile unsigned * unsafe p_tail_index = (volatile unsigned * unsafe)(&used.tail_index);
  unsigned tail_index = *p_tail_index;

  return tail_index == head_index;
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

#pragma unsafe arrays
unsafe void rgmii_buffer_manager(streaming chanend c_rx,
                                 streaming chanend c_speed_change,
                                 buffers_used_t &used_buffers_rx_lp,
                                 buffers_used_t &used_buffers_rx_hp,
                                 buffers_free_t &free_buffers)
{
  set_core_fast_mode_on();

  // Start by issuing buffers to both of the miis
  c_rx <: (uintptr_t)buffers_free_take(free_buffers);

  // Give a second buffer to ensure no delay between packets
  c_rx <: (uintptr_t)buffers_free_take(free_buffers);

  int done = 0;
  while (!done) {
    select {
      case c_rx :> uintptr_t buffer :
        // Get the next available buffer
        uintptr_t next_buffer = (uintptr_t)buffers_free_take(free_buffers);

        if (next_buffer) {
          // There was a buffer free

          // Ensure it is marked as invalid
          ((mii_packet_t *)next_buffer)->stage = MII_STAGE_EMPTY;
          c_rx <: next_buffer;

          // TODO: filter packet - needs to be fixed time filtering
          int filter_result = ethernet_filter_result_set_hp(1, 1);

          if (filter_result) {
            mii_packet_t *buf = (mii_packet_t *)buffer;
            buf->filter_result = filter_result;
            buf->stage = MII_STAGE_FILTERED;
            buf->filter_data = 0;

            if (ethernet_filter_result_is_hp(filter_result))
                buffers_used_add(used_buffers_rx_hp, (mii_packet_t *)buffer);
            else
                buffers_used_add(used_buffers_rx_lp, (mii_packet_t *)buffer);
          }
          else {
            // Drop the packet
            buffers_free_add(free_buffers, (mii_packet_t *)buffer);
          }
        }
        else {
          // There are no buffers available. Drop this packet and reuse buffer.
          ((mii_packet_t *)buffer)->stage = MII_STAGE_EMPTY;
          c_rx <: buffer;
        }
        break;

      case c_speed_change :> unsigned tmp:
        done = 1;
        break;
    }
  }

  // Clean up before changing speed
  empty_channel(c_rx);
}

unsafe static void handle_incoming_packet(rx_client_state_t client_state[n],
                                          server ethernet_rx_if i_rx[n],
                                          unsigned n,
                                          buffers_used_t &used_buffers,
                                          buffers_free_t &free_buffers)
{
  if (buffers_used_empty(used_buffers))
    return;

  mii_packet_t * unsafe buf = (mii_packet_t *)buffers_used_head(used_buffers);
  if (buf->stage != MII_STAGE_FILTERED)
    return;

  // This buffer will now be passed on or dropped - remove from list
  buffers_used_take(used_buffers);

  int tcount = 0;
  if (buf->stage == MII_STAGE_FILTERED) {
    if (buf->filter_result) {
      for (int i = 0; i < n; i++) {
        int client_wants_packet = 1;
        if (client_wants_packet) {
          int wrptr = client_state[i].wrIndex;
          int new_wrptr = wrptr + 1;
          if (new_wrptr >= ETHERNET_RX_CLIENT_QUEUE_SIZE) {
            new_wrptr = 0;
          }
          if (new_wrptr != client_state[i].rdIndex) {
            client_state[i].fifo[wrptr] = buf;
            tcount++;
            i_rx[i].packet_ready();
            client_state[i].wrIndex = new_wrptr;

          } else {
            client_state[i].dropped_pkt_cnt += 1;
          }
        }
      }
    }
  }

  if (tcount == 0) {
    // Packet filtered or not wanted or no-one wanted the buffer so release it
    buffers_free_add(free_buffers, buf);
  } else {
    buf->tcount = tcount - 1;
  }
}

unsafe void rgmii_ethernet_rx_server_aux(rx_client_state_t client_state_lp[n_rx_lp],
                                         server ethernet_rx_if i_rx_lp[n_rx_lp], unsigned n_rx_lp,
                                         streaming chanend ? c_rx_hp,
                                         streaming chanend c_speed_change,
                                         out port p_txclk_out,
                                         in buffered port:4 p_rxd_interframe,
                                         buffers_used_t &used_buffers_rx_lp,
                                         buffers_used_t &used_buffers_rx_hp,
                                         buffers_free_t &free_buffers,
                                         rgmii_inband_status_t current_mode)
{
  set_core_fast_mode_on();

  set_port_inv(p_txclk_out);

  // Signal to the testbench that the device is ready
  enable_rgmii(RGMII_DELAY, RGMII_DIVIDE_1G);

  // Ensure that interrupts will be generated on this core
  install_speed_change_handler(p_rxd_interframe, current_mode);

  ethernet_link_state_t link_status = ETHERNET_LINK_DOWN;

  int done = 0;
  while (1) {
    select {
      case i_rx_lp[int i].get_index() -> size_t result:
        result = i;
        break;

      case i_rx_lp[int i].get_packet(ethernet_packet_info_t &desc, char data[n], unsigned n):
        if (client_state_lp[i].status_update_state == STATUS_UPDATE_PENDING) {
          data[0] = 1;
          data[1] = link_status;
          desc.type = ETH_IF_STATUS;
          client_state_lp[i].status_update_state = STATUS_UPDATE_WAITING;
        }
        else if (client_state_lp[i].rdIndex != client_state_lp[i].wrIndex) {
          // send received packet
          int rdIndex = client_state_lp[i].rdIndex;
          mii_packet_t * unsafe buf = client_state_lp[i].fifo[rdIndex];
          ethernet_packet_info_t info;
          info.type = ETH_DATA;
          info.src_ifnum = 0; // There is only one RGMII port
          info.timestamp = buf->timestamp;
          info.len = buf->length;
          info.filter_data = buf->filter_data;
          memcpy(&desc, &info, sizeof(info));
          memcpy(data, buf->data, buf->length);
          if (mii_get_and_dec_transmit_count(buf) == 0) {
            buffers_free_add(free_buffers, buf);
          }
          if (rdIndex == ETHERNET_RX_CLIENT_QUEUE_SIZE - 1) {
            client_state_lp[i].rdIndex = 0;
          }
          else {
            client_state_lp[i].rdIndex++;
          }
          if (client_state_lp[i].rdIndex != client_state_lp[i].wrIndex) {
            i_rx_lp[i].packet_ready();
          }
        }
        else {
          desc.type = ETH_NO_DATA;
        }
        break;

      case c_speed_change :> unsigned tmp:
        done = 1;
        break;

      default:
        break;
    }

    if (done)
      break;

    // Loop until all high priority packets have been handled
    while (1) {
      if (buffers_used_empty(used_buffers_rx_hp))
        break;

      mii_packet_t * unsafe buf = (mii_packet_t *)buffers_used_head(used_buffers_rx_hp);
      if (buf->stage != MII_STAGE_FILTERED)
        break;

      buffers_used_take(used_buffers_rx_hp);
      ethernet_packet_info_t info;
      info.type = ETH_DATA;
      info.src_ifnum = 0;
      info.timestamp = buf->timestamp;
      info.len = buf->length;
      info.filter_data = buf->filter_data;
      sout_char_array(c_rx_hp, (char *)&info, sizeof(info));
      sout_char_array(c_rx_hp, (char *)buf->data, buf->length);
      buffers_free_add(free_buffers, buf);
    }

    handle_incoming_packet(client_state_lp, i_rx_lp, n_rx_lp, used_buffers_rx_lp, free_buffers);
  }
}

unsafe void rgmii_ethernet_tx_server_aux(tx_client_state_t client_state_lp[n_tx_lp],
                                         server ethernet_tx_if i_tx_lp[n_tx_lp], unsigned n_tx_lp,
                                         streaming chanend ? c_tx_hp,
                                         streaming chanend c_tx_to_mac,
                                         streaming chanend c_speed_change,
                                         buffers_used_t &used_buffers_tx,
                                         buffers_free_t &free_buffers)
{
  set_core_fast_mode_on();

  int sender_count = 0;
  int work_pending = 0;
  int done = 0;

  // If the acknowledge path is not given some priority then the TX packets can end up
  // continually being received but not being able to be sent on to the MAC
  int prioritize_ack = 0;

  // Acquire a free buffer to store high priority packets if needed
  mii_packet_t * unsafe tx_buf_hp = isnull(c_tx_hp) ? null : buffers_free_take(free_buffers);

  while (!done) {
    if (prioritize_ack)
      prioritize_ack--;

    select {
      case i_tx_lp[int i]._init_send_packet(unsigned n, unsigned dst_port):
        if (client_state_lp[i].send_buffer == null)
          client_state_lp[i].requested_send_buffer_size = 1;
        break;

      [[independent_guard]]
      case (int i = 0; i < n_tx_lp; i++)
        (client_state_lp[i].has_outgoing_timestamp_info) =>
        i_tx_lp[i]._get_outgoing_timestamp() -> unsigned timestamp:
        timestamp = client_state_lp[i].outgoing_timestamp;
        client_state_lp[i].has_outgoing_timestamp_info = 0;
        break;

      [[independent_guard]]
      case (int i = 0; i < n_tx_lp; i++)
        (client_state_lp[i].send_buffer != null && !prioritize_ack) =>
         i_tx_lp[i]._complete_send_packet(char data[n], unsigned n,
                                       int request_timestamp,
                                       unsigned dst_port):

        mii_packet_t * unsafe buf = client_state_lp[i].send_buffer;
        unsigned * unsafe dptr = &buf->data[0];
        memcpy(buf->data, data, n);
        buf->length = n;
        if (request_timestamp)
          buf->timestamp_id = i+1;
        else
          buf->timestamp_id = 0;
        work_pending++;
        buffers_used_add(used_buffers_tx, buf);
        buf->tcount = 0;
        buf->stage = 1;
        client_state_lp[i].send_buffer = null;
        client_state_lp[i].requested_send_buffer_size = 0;
        prioritize_ack += 2;
        break;

      case (tx_buf_hp && !prioritize_ack) => c_tx_hp :> unsigned n_bytes:
        sin_char_array(c_tx_hp, (char *)tx_buf_hp->data, n_bytes);
        work_pending++;
        tx_buf_hp->length = n_bytes;
        buffers_used_add(used_buffers_tx, tx_buf_hp);
        tx_buf_hp->tcount = 0;
        tx_buf_hp->stage = 1;
        tx_buf_hp = buffers_free_take(free_buffers);
        prioritize_ack += 2;
        break;

      case c_tx_to_mac :> uintptr_t buffer:
        sender_count--;
        buffers_free_add(free_buffers, (mii_packet_t *)buffer);
        break;

      case c_speed_change :> unsigned tmp:
        done = 1;
        break;

      default:
        break;
    }

    if (work_pending && (sender_count < 2)) {
      // Send a pointer out to the outputter
      c_tx_to_mac <: (uintptr_t)buffers_used_take(used_buffers_tx);
      work_pending--;
      sender_count++;
    }

    // Ensure there is always a high priority buffer
    if (tx_buf_hp == null)
      tx_buf_hp = buffers_free_take(free_buffers);

    for (int i = 0; i < n_tx_lp; i++) {
      if (client_state_lp[i].requested_send_buffer_size != 0 && client_state_lp[i].send_buffer == null) {
        client_state_lp[i].send_buffer = buffers_free_take(free_buffers);
      }
    }
  }

  empty_channel(c_tx_to_mac);
  empty_channel(c_tx_hp);
}

unsafe void rgmii_ethernet_config_server_aux(server ethernet_cfg_if i_cfg[n],
                                             unsigned n,
                                             streaming chanend c_speed_change)
{
  set_core_fast_mode_on();

  char mac_address[6] = {0};
  ethernet_link_state_t link_status = ETHERNET_LINK_DOWN;
  int done = 0;
  while (!done) {
    select {
      case i_cfg[int i].get_macaddr(size_t ifnum, char r_mac_address[6]):
        memcpy(r_mac_address, mac_address, 6);
        break;

      case i_cfg[int i].set_macaddr(size_t ifnum, char r_mac_address[6]):
        memcpy(mac_address, r_mac_address, 6);
        break;

      case i_cfg[int i].set_link_state(int ifnum, ethernet_link_state_t status):
        /*        if (link_status != status) {
          link_status = status;
          for (int i = 0; i < n; i+=1) {
            if (client_state[i].status_update_state == STATUS_UPDATE_WAITING) {
              client_state[i].status_update_state = STATUS_UPDATE_PENDING;
              i_eth[i].packet_ready();
            }
          }
        }*/
        break;

      case i_cfg[int i].add_macaddr_filter(size_t client_num, int is_hp,
                                           ethernet_macaddr_filter_t entry) ->
                                             ethernet_macaddr_filter_result_t result:
        /*unsafe {
          c_macaddr_filter <: 0;
          eth_global_filter_info_t * unsafe p;
          c_macaddr_filter :> p;
          result = ethernet_add_filter_table_entry(*p, i, entry);
          c_macaddr_filter <: 0;
          }*/
        result = 0;
        break;

      case i_cfg[int i].del_macaddr_filter(size_t client_num, int is_hp,
                                           ethernet_macaddr_filter_t entry):
        /*        unsafe {
          c_macaddr_filter <: 0;
          eth_global_filter_info_t * unsafe p;
          c_macaddr_filter :> p;
          ethernet_del_filter_table_entry(*p, i, entry);
          c_macaddr_filter <: 0;
          }*/
        break;

      case i_cfg[int i].del_all_macaddr_filters(size_t client_num, int is_hp):
        /*unsafe {
          c_macaddr_filter <: 0;
          eth_global_filter_info_t * unsafe p;
          c_macaddr_filter :> p;
          ethernet_clear_filter_table(*p, i);
          c_macaddr_filter <: 0;
          }*/
        break;

      case i_cfg[int i].add_ethertype_filter(size_t client_num, int is_hp, uint16_t ethertype):
        /*        size_t n = client_state[i].num_etype_filters;
        assert(n < ETHERNET_MAX_ETHERTYPE_FILTERS);
        client_state[i].etype_filters[n] = ethertype;
        client_state[i].num_etype_filters = n + 1;
        */
        break;

      case i_cfg[int i].del_ethertype_filter(size_t client_num, int is_hp, uint16_t ethertype):
      /*        size_t j = 0;
        size_t n = client_state[i].num_etype_filters;
        while (j < n) {
          if (client_state[i].etype_filters[j] == ethertype) {
            client_state[i].etype_filters[j] = client_state[i].etype_filters[n-1];
            n--;
          }
          else {
            j++;
          }
        }
        client_state[i].num_etype_filters = n;
      */
        break;

      case c_speed_change :> unsigned tmp:
        done = 1;
        break;
    }
  }
}
