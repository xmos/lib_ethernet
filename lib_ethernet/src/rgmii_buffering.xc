// Copyright (c) 2015-2017, XMOS Ltd, All rights reserved
#include <string.h>
#include "default_ethernet_conf.h"
#include <platform.h>
#include "rgmii_buffering.h"
#include "rgmii.h"
#include "rgmii_consts.h"
#define DEBUG_UNIT RGMII_CLIENT_HANDLER
#include "debug_print.h"
#include "print.h"
#include "xassert.h"
#include "macaddr_filter_hash.h"
#include "server_state.h"

unsafe void notify_speed_change(int speed_change_ids[6]) {
  for (int i=0; i < 6; i++) {
    asm("out res[%0], %1"::"r"(speed_change_ids[i]), "r"(0));
  }
}

static inline unsigned int get_tile_id_from_chanend(streaming chanend c) {
  unsigned int tile_id;
  asm("shr %0, %1, 16":"=r"(tile_id):"r"(c));
  return tile_id;
}

#ifndef RGMII_RX_BUFFERS_THRESHOLD
// When using the high priority queue and there are less than this number of buffers
// free then low priority packets start to be dropped
#define RGMII_RX_BUFFERS_THRESHOLD (RGMII_MAC_BUFFER_COUNT_RX / 2)
#endif

#define LOCK(buffers) hwlock_acquire(ethernet_memory_lock)
#define UNLOCK(buffers) hwlock_release(ethernet_memory_lock)

void buffers_free_initialize(buffers_free_t &free, unsigned char *buffer,
                             unsigned *pointers, unsigned buffer_count)
{
  free.top_index = buffer_count;
  unsafe {
    free.stack = (unsigned * unsafe)pointers;
    free.stack[0] = (uintptr_t)buffer;
    for (unsigned i = 1; i < buffer_count; i++)
      free.stack[i] = free.stack[i - 1] + sizeof(mii_packet_t);
  }
}

void buffers_used_initialize(buffers_used_t &used, unsigned *pointers)
{
  used.head_index = 0;
  used.tail_index = 0;
  unsafe {
    used.pointers = pointers;
  }
}

static inline unsigned buffers_free_available(buffers_free_t &free)
{
  return free.top_index;
}

#pragma unsafe arrays
static unsafe inline mii_packet_t * unsafe buffers_free_take(buffers_free_t &free, int do_lock)
{
  if (do_lock) {
    LOCK(free);
  }

  mii_packet_t * unsafe buf = NULL;

  // Ensure that the compiler does not keep this value in a register
  volatile unsigned * unsafe p_top_index = (volatile unsigned * unsafe)(&free.top_index);
  unsigned top_index = *p_top_index;

  if (top_index != 0) {
    top_index--;
    buf = (mii_packet_t *)free.stack[top_index];
    *p_top_index = top_index;
  }

  if (do_lock) {
    UNLOCK(free);
  }
  return buf;
}

#pragma unsafe arrays
static unsafe inline void buffers_free_add(buffers_free_t &free, mii_packet_t * unsafe buf, int do_lock)
{
  if (do_lock) {
    LOCK(free);
  }

  // Ensure that the compiler does not keep this value in a register
  volatile unsigned * unsafe p_top_index = (volatile unsigned * unsafe)(&free.top_index);
  unsigned top_index = *p_top_index;

  unsafe {
    free.stack[top_index] = (uintptr_t)buf;
  }
  top_index++;
  *p_top_index = top_index;

  if (do_lock) {
    UNLOCK(free);
  }
}

#pragma unsafe arrays
static unsafe inline unsafe uintptr_t * unsafe buffers_used_add(buffers_used_t &used,
                                                                mii_packet_t * unsafe buf,
                                                                unsigned buffer_count,
                                                                int do_lock)
{
  if (do_lock) {
    LOCK(free);
  }

  // Ensure that the compiler does not keep this value in a register
  volatile unsigned * unsafe p_head_index = (volatile unsigned * unsafe)(&used.head_index);
  unsigned head_index = *p_head_index;

  unsigned index = head_index % buffer_count;
  used.pointers[index] = (uintptr_t)buf;
  *p_head_index = head_index + 1;

  if (do_lock) {
    UNLOCK(free);
  }

  return &used.pointers[index];
}

#pragma unsafe arrays
static unsafe inline mii_packet_t * unsafe buffers_used_take(buffers_used_t &used,
                                                             unsigned buffer_count,
                                                             int do_lock)
{
  if (do_lock) {
    LOCK(free);
  }

  // Ensure that the compiler does not keep this value in a register
  volatile unsigned * unsafe p_tail_index = (volatile unsigned * unsafe)(&used.tail_index);
  unsigned tail_index = *p_tail_index;
  unsigned index = tail_index % buffer_count;
  *p_tail_index = tail_index + 1;

  unsafe {
    mii_packet_t * unsafe buf = (mii_packet_t *)used.pointers[index];
    if (do_lock) {
      UNLOCK(free);
    }
    return buf;
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
                                 buffers_free_t &free_buffers,
                                 unsigned filter_num)
{
  set_core_fast_mode_on();

  // Start by issuing buffers to both of the miis
  c_rx <: (uintptr_t)buffers_free_take(free_buffers, 1);

  // Give a second buffer to ensure no delay between packets
  c_rx <: (uintptr_t)buffers_free_take(free_buffers, 1);

  int done = 0;
  while (!done) {
    mii_macaddr_hash_table_t * unsafe table = mii_macaddr_get_hash_table(filter_num);

    select {
      case c_rx :> uintptr_t buffer :
        // Get the next available buffer
        uintptr_t next_buffer = (uintptr_t)buffers_free_take(free_buffers, 1);

        if (next_buffer) {
          // There was a buffer free
          mii_packet_t *buf = (mii_packet_t *)buffer;

          // Ensure it is marked as invalid
          c_rx <: next_buffer;

          // Use the destination MAC addresses as the key for the hash
          unsigned key0 = buf->data[0];
          unsigned key1 = buf->data[1] & 0xffff;
          unsigned filter_result = mii_macaddr_hash_lookup(table, key0, key1, &buf->filter_data);
          if (filter_result) {
            buf->filter_result = filter_result;

            if (ethernet_filter_result_is_hp(filter_result))
              buffers_used_add(used_buffers_rx_hp, (mii_packet_t *)buffer, RGMII_MAC_BUFFER_COUNT_RX, 1);
            else
              buffers_used_add(used_buffers_rx_lp, (mii_packet_t *)buffer, RGMII_MAC_BUFFER_COUNT_RX, 1);
          }
          else {
            // Drop the packet
            buffers_free_add(free_buffers, (mii_packet_t *)buffer, 1);
          }
        }
        else {
          // There are no buffers available. Drop this packet and reuse buffer.
          c_rx <: buffer;
        }
        break;

      case c_speed_change :> unsigned tmp:
        done = 1;
        break;

      default:
        // Ensure that the hash table pointer is being updated even when
        // there are no packets on the wire
        break;
    }
  }

  // Clean up before changing speed
  empty_channel(c_rx);
}

unsafe static void handle_incoming_packet(rx_client_state_t client_states[n],
                                          server ethernet_rx_if i_rx[n],
                                          unsigned n,
                                          buffers_used_t &used_buffers,
                                          buffers_free_t &free_buffers)
{
  if (buffers_used_empty(used_buffers))
    return;

  mii_packet_t * unsafe buf = (mii_packet_t *)buffers_used_take(used_buffers, RGMII_MAC_BUFFER_COUNT_RX, 1);

  int tcount = 0;
  if (buf->filter_result) {
    for (int i = 0; i < n; i++) {
      rx_client_state_t &client_state = client_states[i];

      int client_wants_packet = ((buf->filter_result >> i) & 1);
      if (client_state.num_etype_filters != 0) {
        char * unsafe data = (char * unsafe) buf->data;
        int passed_etype_filter = 0;
        uint16_t etype = ((uint16_t) data[12] << 8) + data[13];
        int qhdr = (etype == 0x8100);
        if (qhdr) {
          // has a 802.1q tag - read etype from next word
          etype = ((uint16_t) data[16] << 8) + data[17];
        }
        for (int j = 0; j < client_state.num_etype_filters; j++) {
          if (client_state.etype_filters[j] == etype) {
            passed_etype_filter = 1;
            break;
          }
        }
        client_wants_packet &= passed_etype_filter;
      }

      if (client_wants_packet) {
        int wrptr = client_state.wr_index;
        int new_wrptr = wrptr + 1;
        if (new_wrptr >= ETHERNET_RX_CLIENT_QUEUE_SIZE) {
          new_wrptr = 0;
        }
        if (new_wrptr != client_state.rd_index) {
          client_state.fifo[wrptr] = (void *)buf;
          tcount++;
          i_rx[i].packet_ready();
          client_state.wr_index = new_wrptr;

        } else {
          client_state.dropped_pkt_cnt += 1;
        }
      }
    }
  }

  if (tcount == 0) {
    // Packet filtered or not wanted or no-one wanted the buffer so release it
    buffers_free_add(free_buffers, buf, 1);
  } else {
    buf->tcount = tcount - 1;
  }
}

unsafe static void drop_lp_packets(rx_client_state_t client_states[n], unsigned n,
                                   buffers_used_t &used_buffers_rx_lp,
                                   buffers_free_t &free_buffers)
{
  for (int i = 0; i < n; i++) {
    rx_client_state_t &client_state = client_states[i];

    unsigned rd_index = client_state.rd_index;
    if (rd_index != client_state.wr_index) {
      mii_packet_t * unsafe buf = (mii_packet_t * unsafe)client_state.fifo[rd_index];

      if (mii_get_and_dec_transmit_count(buf) == 0) {
        buffers_free_add(free_buffers, buf, 1);
      }
      client_state.rd_index = increment_and_wrap_power_of_2(rd_index,
                                                            ETHERNET_RX_CLIENT_QUEUE_SIZE);
      client_state.dropped_pkt_cnt += 1;
    }
  }
}

unsafe rgmii_inband_status_t get_current_rgmii_mode(in buffered port:4 p_rxd_interframe,
                                                    rgmii_inband_status_t last_mode,
                                                    int speed_change_ids[6])
{
  timer t;
  unsigned time;
  rgmii_inband_status_t mode[2];
  clearbuf(p_rxd_interframe);
  t :> time;

  // Read the interframe RGMII mode twice to ensure that we do not trigger
  // on any of the reserved patterns (when GMII_RX_DV=0, GMII_RX_ER=1)
  for (int i=0; i < 2; i++) {
    select {
      case p_rxd_interframe :> mode[i]:
        if (mode[i] < INBAND_STATUS_10M_FULLDUPLEX_DOWN ||
            mode[i] > INBAND_STATUS_1G_FULLDUPLEX_UP) {
          return last_mode;
        }
        if (i == 1) {
          if ((mode[0] == mode[1]) &&
              (last_mode != mode[0])) {
            notify_speed_change(speed_change_ids);
            return mode[0];
          }
          else {
            return last_mode;
          }
        }
        t :> time;
        break;
      // Timeout and return if there is no data in the interframe port.
      // Some PHYs will hibernate and turn off the RX clock which will cause successive
      // reads to block. We do not want to block the RX server.
      case t when timerafter(time + 100) :> void:
        return last_mode;
        break;
    }
  }
  __builtin_unreachable();
  return last_mode;
}

unsafe void rgmii_ethernet_rx_server(rx_client_state_t client_state_lp[n_rx_lp],
                                     server ethernet_rx_if i_rx_lp[n_rx_lp], unsigned n_rx_lp,
                                     streaming chanend ? c_rx_hp,
                                     streaming chanend c_rgmii_cfg,
                                     out port p_txclk_out,
                                     in buffered port:4 p_rxd_interframe,
                                     buffers_used_t &used_buffers_rx_lp,
                                     buffers_used_t &used_buffers_rx_hp,
                                     buffers_free_t &free_buffers,
                                     rgmii_inband_status_t &current_mode,
                                     int speed_change_ids[6],
                                     volatile ethernet_port_state_t * unsafe p_port_state)
{
  timer tmr;
  int t;
  tmr :> t;
  const int rgmii_mode_poll_period_ms = __SIMULATOR__ ? 1 : 100;

  set_core_fast_mode_on();

  if (current_mode == INBAND_STATUS_1G_FULLDUPLEX_UP ||
      current_mode == INBAND_STATUS_1G_FULLDUPLEX_DOWN) {
    enable_rgmii(RGMII_DELAY, RGMII_DIVIDE_1G);
  }
  else {
    enable_rgmii(RGMII_DELAY_100M, RGMII_DIVIDE_100M);
  }

  ethernet_link_state_t cur_link_state = p_port_state->link_state;

  unsafe {
    c_rgmii_cfg <: (rx_client_state_t * unsafe) client_state_lp;
    c_rgmii_cfg <: n_rx_lp;
    c_rgmii_cfg <: p_port_state;
  }

  int done = 0;
  while (1) {
    select {
      case i_rx_lp[int i].get_index() -> size_t result:
        result = i;
        break;

      case i_rx_lp[int i].get_packet(ethernet_packet_info_t &desc, char data[n], unsigned n):
        rx_client_state_t &client_state = client_state_lp[i];

        if (client_state.status_update_state == STATUS_UPDATE_PENDING) {
          data[0] = cur_link_state;
          data[1] = p_port_state->link_speed;
          desc.type = ETH_IF_STATUS;
          desc.src_ifnum = 0;
          desc.timestamp = 0;
          desc.len = 2;
          desc.filter_data = 0;
          client_state.status_update_state = STATUS_UPDATE_WAITING;
        }
        else if (client_state.rd_index != client_state.wr_index) {
          // send received packet
          int rd_index = client_state.rd_index;
          mii_packet_t * unsafe buf = (mii_packet_t * unsafe)client_state.fifo[rd_index];
          ethernet_packet_info_t info;
          info.type = ETH_DATA;
          info.src_ifnum = 0; // There is only one RGMII port
          info.timestamp = buf->timestamp - p_port_state->ingress_ts_latency[p_port_state->link_speed];
          info.len = buf->length;
          info.filter_data = buf->filter_data;
          memcpy(&desc, &info, sizeof(info));
          memcpy(data, buf->data, buf->length);
          if (mii_get_and_dec_transmit_count(buf) == 0) {
            buffers_free_add(free_buffers, buf, 1);
          }

          client_state.rd_index = increment_and_wrap_power_of_2(client_state.rd_index,
                                                                ETHERNET_RX_CLIENT_QUEUE_SIZE);

          if (client_state.rd_index != client_state.wr_index) {
            i_rx_lp[i].packet_ready();
          }
        }
        else {
          desc.type = ETH_NO_DATA;
        }
        break;

      case tmr when timerafter(t) :> t:
        rgmii_inband_status_t new_mode = get_current_rgmii_mode(p_rxd_interframe, current_mode, speed_change_ids);

        if (new_mode != current_mode) {
          current_mode = new_mode;
          done = 1;
        }

        t += rgmii_mode_poll_period_ms * XS1_TIMER_KHZ;
        break;

      default:
        break;
    }

    if (done)
      break;

    unsafe {
      if (cur_link_state != p_port_state->link_state) {
        cur_link_state = p_port_state->link_state;
        for (int i = 0; i < n_rx_lp; i += 1) {
          if (client_state_lp[i].status_update_state == STATUS_UPDATE_WAITING) {
            client_state_lp[i].status_update_state = STATUS_UPDATE_PENDING;
            i_rx_lp[i].packet_ready();
          }
        }
      }
    }

    // Loop until all high priority packets have been handled
    while (1) {
      if (buffers_used_empty(used_buffers_rx_hp))
        break;

      mii_packet_t * unsafe buf = (mii_packet_t *)buffers_used_take(used_buffers_rx_hp,
                                                                    RGMII_MAC_BUFFER_COUNT_RX, 1);

      if (!isnull(c_rx_hp)) {
        ethernet_packet_info_t info;
        info.type = ETH_DATA;
        info.src_ifnum = 0;
        info.timestamp = buf->timestamp - p_port_state->ingress_ts_latency[p_port_state->link_speed];
        info.len = buf->length;
        info.filter_data = buf->filter_data;
        sout_char_array(c_rx_hp, (char *)&info, sizeof(info));
        sout_char_array(c_rx_hp, (char *)buf->data, buf->length);
      }
      buffers_free_add(free_buffers, buf, 1);
    }

    handle_incoming_packet(client_state_lp, i_rx_lp, n_rx_lp, used_buffers_rx_lp, free_buffers);

    if (buffers_free_available(free_buffers) <= RGMII_RX_BUFFERS_THRESHOLD) {
      drop_lp_packets(client_state_lp, n_rx_lp, used_buffers_rx_lp, free_buffers);
    }
  }
}

unsafe void rgmii_ethernet_tx_server(tx_client_state_t client_state_lp[n_tx_lp],
                                     server ethernet_tx_if i_tx_lp[n_tx_lp], unsigned n_tx_lp,
                                     streaming chanend ? c_tx_hp,
                                     streaming chanend c_tx_to_mac,
                                     streaming chanend c_speed_change,
                                     buffers_used_t &used_buffers_tx_lp,
                                     buffers_free_t &free_buffers_lp,
                                     buffers_used_t &used_buffers_tx_hp,
                                     buffers_free_t &free_buffers_hp,
                                     volatile ethernet_port_state_t * unsafe p_port_state)
{
  set_core_fast_mode_on();
  int enable_shaper = p_port_state->qav_shaper_enabled;

  timer tmr;
  int credit = 0;
  int credit_time;
  tmr :> credit_time;

  int sender_count = 0;
  int work_pending = 0;
  int done = 0;

  // If the acknowledge path is not given some priority then the TX packets can end up
  // continually being received but not being able to be sent on to the MAC
  int prioritize_ack = 0;

  // Acquire a free buffer to store high priority packets if needed
  mii_packet_t * unsafe tx_buf_hp = isnull(c_tx_hp) ? null : buffers_free_take(free_buffers_hp, 0);

  while (!done) {
    if (prioritize_ack)
      prioritize_ack--;

    select {
      case i_tx_lp[int i]._init_send_packet(unsigned n, unsigned dst_port):
        if (client_state_lp[i].send_buffer == null) {
          client_state_lp[i].requested_send_buffer_size = 1;
        }
        break;

      [[independent_guard]]
      case (int i = 0; i < n_tx_lp; i++)
        (client_state_lp[i].has_outgoing_timestamp_info) =>
        i_tx_lp[i]._get_outgoing_timestamp() -> unsigned timestamp:
        timestamp = client_state_lp[i].outgoing_timestamp + p_port_state->egress_ts_latency[p_port_state->link_speed];
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
        if (request_timestamp) {
          buf->timestamp_id = i+1;
        }
        else {
          buf->timestamp_id = 0;
        }

        // Indicate in the filter_data that this is a low priority buffer
        buf->filter_data = 0;

        work_pending++;
        buffers_used_add(used_buffers_tx_lp, buf, RGMII_MAC_BUFFER_COUNT_TX, 0);
        buf->tcount = 0;
        client_state_lp[i].send_buffer = null;
        client_state_lp[i].requested_send_buffer_size = 0;
        prioritize_ack += 2;
        break;

      case (tx_buf_hp && !prioritize_ack) => c_tx_hp :> unsigned n_bytes:
        sin_char_array(c_tx_hp, (char *)tx_buf_hp->data, n_bytes);
        tx_buf_hp->length = n_bytes;
        tx_buf_hp->timestamp_id = 0;

        // Indicate in the filter_data that this is a high priority buffer
        tx_buf_hp->filter_data = 1;
        work_pending++;
        buffers_used_add(used_buffers_tx_hp, tx_buf_hp, RGMII_MAC_BUFFER_COUNT_TX, 0);
        tx_buf_hp->tcount = 0;
        tx_buf_hp = buffers_free_take(free_buffers_hp, 0);
        prioritize_ack += 2;
        break;

      case c_tx_to_mac :> uintptr_t buffer: {
        sender_count--;
        mii_packet_t *buf = (mii_packet_t *)buffer;
        if (buf->filter_data) {
          // High priority packet sent
          buffers_free_add(free_buffers_hp, buf, 0);
        }
        else {
          // Low priority packet sent
          if (buf->timestamp_id) {
            size_t client_id = buf->timestamp_id - 1;
            client_state_lp[client_id].has_outgoing_timestamp_info = 1;
            client_state_lp[client_id].outgoing_timestamp = buf->timestamp + p_port_state->egress_ts_latency[p_port_state->link_speed];
          }
          buffers_free_add(free_buffers_lp, buf, 0);
        }
        break;
      }

      case c_speed_change :> unsigned tmp:
        done = 1;
        break;

      default:
        break;
    }

    if (enable_shaper) {
      int prev_credit_time = credit_time;
      tmr :> credit_time;

      int elapsed = credit_time - prev_credit_time;
      credit += elapsed * p_port_state->qav_idle_slope;

      if (buffers_used_empty(used_buffers_tx_hp)) {
        // Keep the credit 0 when there are no high priority buffers
        if (credit > 0) {
          credit = 0;
        }
      }
    }

    if (work_pending && (sender_count < 2)) {
      int packet_is_high_priority = 1;
      mii_packet_t * unsafe buf = null;

      if (ETHERNET_SUPPORT_HP_QUEUES) {
        if (enable_shaper) {
          if (!buffers_used_empty(used_buffers_tx_hp)) {
            // Once there is enough credit then take the next buffer
            if (credit >= 0) {
              buf = buffers_used_take(used_buffers_tx_hp, RGMII_MAC_BUFFER_COUNT_TX, 0);
            }
          }
        }
        else {
          if (!buffers_used_empty(used_buffers_tx_hp)) {
            buf = buffers_used_take(used_buffers_tx_hp, RGMII_MAC_BUFFER_COUNT_TX, 0);
          }
        }
      }

      if (!buf && !buffers_used_empty(used_buffers_tx_lp)) {
        buf = buffers_used_take(used_buffers_tx_lp, RGMII_MAC_BUFFER_COUNT_TX, 0);
        packet_is_high_priority = 0;
      }

      if (buf) {
        // Send a pointer out to the outputter
        c_tx_to_mac <: buf;
        work_pending--;
        sender_count++;

        if (enable_shaper && packet_is_high_priority) {
          const int preamble_bytes = 8;
          const int ifg_bytes = 96/8;
          const int crc_bytes = 4;
          int len = buf->length + preamble_bytes + ifg_bytes + crc_bytes;
          credit = credit - (len << (MII_CREDIT_FRACTIONAL_BITS+3));
        }
      }
    }

    // Ensure there is always a high priority buffer
    if (!isnull(c_tx_hp) && (tx_buf_hp == null)) {
      tx_buf_hp = buffers_free_take(free_buffers_hp, 0);
    }

    for (int i = 0; i < n_tx_lp; i++) {
      if (client_state_lp[i].requested_send_buffer_size != 0 && client_state_lp[i].send_buffer == null) {
        client_state_lp[i].send_buffer = buffers_free_take(free_buffers_lp, 0);
      }
    }
  }

  empty_channel(c_tx_to_mac);
  if (!isnull(c_tx_hp)) {
    empty_channel(c_tx_hp);
  }
}

[[combinable]]
void rgmii_ethernet_mac_config(server ethernet_cfg_if i_cfg[n],
                               unsigned n,
                               streaming chanend c_rgmii_cfg)
{
  set_core_fast_mode_on();

  uint8_t mac_address[MACADDR_NUM_BYTES] = {0};
  volatile rx_client_state_t * unsafe client_state_lp;
  unsigned n_rx_lp;
  volatile ethernet_port_state_t * unsafe p_port_state;

  // Get shared state from the server
  unsafe {
    c_rgmii_cfg :> client_state_lp;
    c_rgmii_cfg :> n_rx_lp;
    c_rgmii_cfg :> p_port_state;
  }

  while (1) {
    select {
      case i_cfg[int i].get_macaddr(size_t ifnum, uint8_t r_mac_address[MACADDR_NUM_BYTES]):
        memcpy(r_mac_address, mac_address, sizeof mac_address);
        break;

      case i_cfg[int i].set_macaddr(size_t ifnum, uint8_t r_mac_address[MACADDR_NUM_BYTES]):
        memcpy(mac_address, r_mac_address, sizeof r_mac_address);
        break;

      case i_cfg[int i].set_link_state(int ifnum, ethernet_link_state_t status, ethernet_speed_t speed):
        unsafe {
          p_port_state->link_state = status;
          p_port_state->link_speed = speed;
        }
        break;

      case i_cfg[int i].add_macaddr_filter(size_t client_num, int is_hp,
                                           ethernet_macaddr_filter_t entry) ->
                                             ethernet_macaddr_filter_result_t result:
        result = mii_macaddr_hash_table_add_entry(client_num, is_hp, entry);
        break;

      case i_cfg[int i].del_macaddr_filter(size_t client_num, int is_hp,
                                           ethernet_macaddr_filter_t entry):
        mii_macaddr_hash_table_delete_entry(client_num, is_hp, entry);
        break;

      case i_cfg[int i].del_all_macaddr_filters(size_t client_num, int is_hp):
        mii_macaddr_hash_table_clear();
        break;

      case i_cfg[int i].add_ethertype_filter(size_t client_num, uint16_t ethertype):
        unsafe {
          rx_client_state_t &client_state = client_state_lp[client_num];
          size_t n = client_state.num_etype_filters;
          assert(n < ETHERNET_MAX_ETHERTYPE_FILTERS);
          client_state.etype_filters[n] = ethertype;
          client_state.num_etype_filters = n + 1;
        }
        break;

      case i_cfg[int i].del_ethertype_filter(size_t client_num, uint16_t ethertype):
        unsafe {
          rx_client_state_t &client_state = client_state_lp[client_num];
          size_t j = 0;
          size_t n = client_state.num_etype_filters;
          while (j < n) {
            if (client_state.etype_filters[j] == ethertype) {
              client_state.etype_filters[j] = client_state.etype_filters[n-1];
              n--;
            }
            else {
              j++;
            }
          }
          client_state.num_etype_filters = n;
        }
        break;

      case i_cfg[int i].get_tile_id_and_timer_value(unsigned &tile_id, unsigned &time_on_tile): {
        tile_id = get_tile_id_from_chanend(c_rgmii_cfg);

        timer tmr;
        tmr :> time_on_tile;
        break;
      }

      case i_cfg[int i].set_egress_qav_idle_slope(size_t ifnum, unsigned slope): {
        unsafe {
          p_port_state->qav_idle_slope = slope;
        }
        break;
      }

      case i_cfg[int i].set_ingress_timestamp_latency(size_t ifnum, ethernet_speed_t speed, unsigned value): {
        if (speed < 0 || speed >= NUM_ETHERNET_SPEEDS) {
          fail("Invalid Ethernet speed, must be a valid ethernet_speed_t enum value");
        }
        unsafe {
          p_port_state->ingress_ts_latency[speed] = value / 10;
        }
        break;
      }

      case i_cfg[int i].set_egress_timestamp_latency(size_t ifnum, ethernet_speed_t speed, unsigned value): {
        if (speed < 0 || speed >= NUM_ETHERNET_SPEEDS) {
          fail("Invalid Ethernet speed, must be a valid ethernet_speed_t enum value");
        }
        unsafe {
          p_port_state->egress_ts_latency[speed] = value / 10;
        }
        break;
      }

      case i_cfg[int i].enable_strip_vlan_tag(size_t client_num):
        fail("VLAN tag stripping not supported in Gigabit Ethernet MAC");
        break;

      case i_cfg[int i].disable_strip_vlan_tag(size_t client_num):
        fail("VLAN tag stripping not supported in Gigabit Ethernet MAC");
        break;

      case i_cfg[int i].enable_link_status_notification(size_t client_num):
        unsafe {
          rx_client_state_t &client_state = client_state_lp[client_num];
          client_state.status_update_state = STATUS_UPDATE_WAITING;
          break;
        }

      case i_cfg[int i].disable_link_status_notification(size_t client_num):
        unsafe {
          rx_client_state_t &client_state = client_state_lp[client_num];
          client_state.status_update_state = STATUS_UPDATE_IGNORING;
          break;
        }

      case c_rgmii_cfg :> unsigned tmp:
        // Server has reset
        unsafe {
          client_state_lp = (volatile rx_client_state_t * unsafe) tmp;
          c_rgmii_cfg :> n_rx_lp;
          c_rgmii_cfg :> p_port_state;
        }
        break;
    }
  }
}
