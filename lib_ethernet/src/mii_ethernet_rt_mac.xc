// Copyright (c) 2013-2017, XMOS Ltd, All rights reserved
#include <string.h>

#include "ethernet.h"
#include "default_ethernet_conf.h"
#include "mii_master.h"
#include "mii_filter.h"
#include "mii_buffering.h"
#include "mii_ts_queue.h"
#include "client_state.h"
#define DEBUG_UNIT ETHERNET_CLIENT_HANDLER
#include "debug_print.h"
#include "xassert.h"
#include "print.h"
#include "server_state.h"

static inline unsigned int get_tile_id_from_chanend(chanend c) {
  unsigned int tile_id;
  asm("shr %0, %1, 16":"=r"(tile_id):"r"(c));
  return tile_id;
}

#ifndef MII_RX_THRESHOLD_BYTES
// When using the high priority queue and there are less than this number of bytes
// free then low priority packets start to be dropped
#define MII_RX_THRESHOLD_BYTES 2000
#endif

unsafe static void reserve(tx_client_state_t client_state[n], unsigned n, mii_mempool_t mem, unsigned * unsafe rdptr)
{
  for (int i = 0; i < n; i++) {
    if (client_state[i].requested_send_buffer_size != 0 &&
        client_state[i].send_buffer == null) {
      debug_printf("Trying to reserve send buffer (client %d, size %d)\n",
                   i, client_state[i].requested_send_buffer_size);

      client_state[i].send_buffer =
        mii_reserve_at_least(mem, rdptr, client_state[i].requested_send_buffer_size + sizeof(mii_packet_t));
    }
  }
}

unsafe static void handle_incoming_packet(mii_packet_queue_t packets,
                                          unsigned &rd_index,
                                          rx_client_state_t client_states[n],
                                          server ethernet_rx_if i_rx[n],
                                          unsigned n)
{
  mii_packet_t * unsafe buf = mii_get_my_next_buf(packets, rd_index);
  if (!buf)
    return;

  int tcount = 0;
  if (buf->filter_result) {
    for (int i = 0; i < n; i++) {
      rx_client_state_t &client_state = client_states[i];

      int client_wants_packet = ((buf->filter_result >> i) & 1);
      char * unsafe data = (char * unsafe) buf->data;
      int passed_etype_filter = 0;
      uint16_t etype = ((uint16_t) data[12] << 8) + data[13];
      int qhdr = (etype == 0x8100);
      if (qhdr) {
        // has a 802.1q tag - read etype from next word
        etype = ((uint16_t) data[16] << 8) + data[17];
        buf->vlan_tagged = 1;
      }
      else {
        buf->vlan_tagged = 0;
      }
      if (client_state.num_etype_filters != 0) {
        for (int j = 0; j < client_state.num_etype_filters; j++) {
          if (client_state.etype_filters[j] == etype) {
            passed_etype_filter = 1;
            break;
          }
        }
        client_wants_packet &= passed_etype_filter;
      }

      if (client_wants_packet) {
        debug_printf("Trying to queue for client %d\n", i);
        int wr_index = client_state.wr_index;
        int new_wr_index = increment_and_wrap_to_zero(wr_index,
                                                      ETHERNET_RX_CLIENT_QUEUE_SIZE);

        if (new_wr_index != client_state.rd_index) {
          debug_printf("Putting in client queue %d\n", i);

          // Store the index into the packet queue
          client_state.fifo[wr_index] = (void *)rd_index;
          tcount++;
          i_rx[i].packet_ready();
          client_state.wr_index = new_wr_index;
        } else {
          client_state.dropped_pkt_cnt += 1;
        }
      }
    }
  }

  if (tcount == 0) {
    mii_free_index(packets, rd_index);
  }
  else {
    buf->tcount = tcount - 1;
  }
  // Only move the rd_index after any clients register using it
  rd_index = mii_move_my_rd_index(packets, rd_index);
}

unsafe static void drop_lp_packets(mii_packet_queue_t packets,
                                   rx_client_state_t client_states[n],
                                   unsigned n)
{
  for (int i = 0; i < n; i++) {
    rx_client_state_t &client_state = client_states[i];
    
    if (client_state.rd_index != client_state.wr_index) {
      unsigned client_rd_index = client_state.rd_index;
      unsigned packets_rd_index = (unsigned)client_state.fifo[client_rd_index];

      packet_queue_info_t * unsafe p_packets = (packet_queue_info_t * unsafe)packets;
      mii_packet_t * unsafe buf = (mii_packet_t * unsafe)p_packets->ptrs[packets_rd_index];

      if (mii_get_and_dec_transmit_count(buf) == 0) {
        mii_free_index(packets, packets_rd_index);
      }
      client_state.rd_index = increment_and_wrap_to_zero(client_state.rd_index,
                                                         ETHERNET_RX_CLIENT_QUEUE_SIZE);
      client_state.dropped_pkt_cnt += 1;
    }
  }
}

unsafe static void handle_incoming_hp_packets(mii_mempool_t rxmem,
                                              mii_packet_queue_t packets,
                                              unsigned &rd_index,
                                              rx_client_state_t &client_state,
                                              streaming chanend c_rx_hp,
                                              volatile ethernet_port_state_t * unsafe p_port_state)
{
  while (1) {
    mii_packet_t * unsafe buf = mii_get_my_next_buf(packets, rd_index);
    if (!buf)
      return;

    int client_wants_packet = 0;
    if (buf->filter_result && ethernet_filter_result_is_hp(buf->filter_result)) {
      client_wants_packet = (buf->filter_result & 1);
    }

    if (client_wants_packet)
    {
      unsigned * unsafe wrap_ptr = mii_get_wrap_ptr(rxmem);
      unsigned * unsafe dptr = buf->data;
      unsigned prewrap = ((char *) wrap_ptr - (char *) dptr);
      unsigned len = buf->length;
      unsigned len1 = prewrap > len ? len : prewrap;
      unsigned len2 = prewrap > len ? 0 : len - prewrap;

      ethernet_packet_info_t info;
      info.type = ETH_DATA;
      info.src_ifnum = buf->src_port;
      info.timestamp = buf->timestamp - p_port_state->ingress_ts_latency[p_port_state->link_speed];
      info.len = len1 | len2 << 16;
      info.filter_data = buf->filter_data;

      sout_char_array(c_rx_hp, (char *)&info, sizeof(info));
      sout_char_array(c_rx_hp, (char *)dptr, len1);
      if (len2) {
        sout_char_array(c_rx_hp, (char *)*wrap_ptr, len2);
      }
    }

    rd_index = mii_free_index(packets, rd_index);
  }
}

static inline void update_client_state(rx_client_state_t client_state[n],
                                              server ethernet_rx_if i_rx[n],
                                              unsigned n)
{
  for (int i = 0; i < n; i += 1) {
    if (client_state[i].status_update_state == STATUS_UPDATE_WAITING) {
      client_state[i].status_update_state = STATUS_UPDATE_PENDING;
      i_rx[i].packet_ready();
    }
  }
}

unsafe static inline void handle_ts_queue(mii_ts_queue_t ts_queue,
                                   tx_client_state_t client_state[n],
                                   unsigned n)
{
  unsigned index = 0;
  unsigned timestamp = 0;
  int found = mii_ts_queue_get_entry(ts_queue, &index, &timestamp);
  if (found) {
    size_t client_id = index - 1;
    client_state[client_id].has_outgoing_timestamp_info = 1;
    client_state[client_id].outgoing_timestamp = timestamp;
  }
}

unsafe static void mii_ethernet_server(mii_mempool_t rx_mem,
                                       mii_packet_queue_t rx_packets_lp,
                                       mii_packet_queue_t rx_packets_hp,
                                       unsigned * unsafe rx_rdptr,
                                       mii_mempool_t tx_mem_lp,
                                       mii_mempool_t tx_mem_hp,
                                       mii_packet_queue_t tx_packets_lp,
                                       mii_packet_queue_t tx_packets_hp,
                                       mii_ts_queue_t ts_queue_lp,
                                       server ethernet_cfg_if i_cfg[n_cfg], static const unsigned n_cfg,
                                       server ethernet_rx_if i_rx_lp[n_rx_lp], static const unsigned n_rx_lp,
                                       server ethernet_tx_if i_tx_lp[n_tx_lp], static const unsigned n_tx_lp,
                                       streaming chanend ? c_rx_hp,
                                       streaming chanend ? c_tx_hp,
                                       chanend c_macaddr_filter,
                                       volatile ethernet_port_state_t * unsafe p_port_state)
{
  uint8_t mac_address[MACADDR_NUM_BYTES] = {0};
  rx_client_state_t rx_client_state_lp[n_rx_lp];
  rx_client_state_t rx_client_state_hp[1];
  tx_client_state_t tx_client_state_lp[n_tx_lp];
  tx_client_state_t tx_client_state_hp[1];

  unsigned rd_index_hp = mii_init_my_rd_index(rx_packets_hp);
  unsigned rd_index_lp = mii_init_my_rd_index(rx_packets_lp);

  init_rx_client_state(rx_client_state_lp, n_rx_lp);
  init_rx_client_state(rx_client_state_hp, 1);
  init_tx_client_state(tx_client_state_lp, n_tx_lp);
  init_tx_client_state(tx_client_state_hp, 1);

  tx_client_state_hp[0].requested_send_buffer_size = ETHERNET_MAX_PACKET_SIZE;

  volatile unsigned * unsafe p_rx_rdptr = (volatile unsigned * unsafe)rx_rdptr;

  int prioritize_rx = 0;
  while (1) {
    if (prioritize_rx)
      prioritize_rx--;

    select {
    case i_rx_lp[int i].get_index() -> size_t result:
      result = i;
      break;

    case i_rx_lp[int i].get_packet(ethernet_packet_info_t &desc, char data[n], unsigned n): {
      prioritize_rx += 1;

      rx_client_state_t &client_state = rx_client_state_lp[i];

      if (client_state.status_update_state == STATUS_UPDATE_PENDING) {
        data[0] = p_port_state->link_state;
        data[1] = p_port_state->link_speed;
        desc.type = ETH_IF_STATUS;
        desc.src_ifnum = 0;
        desc.timestamp = 0;
        desc.len = 2;
        desc.filter_data = 0;
        client_state.status_update_state = STATUS_UPDATE_WAITING;
      }
      else if (client_state.rd_index != client_state.wr_index) {
        unsigned client_rd_index = client_state.rd_index;
        unsigned packets_rd_index = (unsigned)client_state.fifo[client_rd_index];

        packet_queue_info_t * unsafe p_packets_lp = (packet_queue_info_t * unsafe)rx_packets_lp;
        mii_packet_t * unsafe buf = (mii_packet_t * unsafe)p_packets_lp->ptrs[packets_rd_index];

        ethernet_packet_info_t info;
        info.type = ETH_DATA;
        info.src_ifnum = buf->src_port;
        info.timestamp = buf->timestamp - p_port_state->ingress_ts_latency[p_port_state->link_speed];
        info.len = buf->length;
        info.filter_data = buf->filter_data;

        int len = (n > buf->length ? buf->length : n);
        unsigned * unsafe wrap_ptr = mii_get_wrap_ptr(rx_mem);
        unsigned * unsafe dptr = buf->data;
        int prewrap = ((char *) wrap_ptr - (char *) dptr);
        int len1 = prewrap > len ? len : prewrap;
        int len2 = prewrap > len ? 0 : len - prewrap;
        if (client_state.strip_vlan_tags && buf->vlan_tagged) {
          memcpy(data, dptr, 12); // Src and dest MAC addresses
          len1 -= 4;
          memcpy(&data[12], (char*)dptr+16, len1); // Copy from index of Ethertype after VLAN tag
          info.len -= 4;
        } else {
          memcpy(data, dptr, len1);
        }
        if (len2) {
          memcpy(&data[len1], (unsigned *) *wrap_ptr, len2);
        }

        memcpy(&desc, &info, sizeof(info));

        if (mii_get_and_dec_transmit_count(buf) == 0) {
          mii_free_index(rx_packets_lp, packets_rd_index);
        }

        client_state.rd_index = increment_and_wrap_to_zero(client_state.rd_index,
                                                           ETHERNET_RX_CLIENT_QUEUE_SIZE);
        if (client_state.rd_index != client_state.wr_index) {
          i_rx_lp[i].packet_ready();
        }
      }
      else  {
        desc.type = ETH_NO_DATA;
      }
      break;
    }

    case i_cfg[int i].get_macaddr(size_t ifnum, uint8_t r_mac_address[MACADDR_NUM_BYTES]):
      memcpy(r_mac_address, mac_address, sizeof mac_address);
      break;

    case i_cfg[int i].set_macaddr(size_t ifnum, uint8_t r_mac_address[MACADDR_NUM_BYTES]):
      memcpy(mac_address, r_mac_address, sizeof r_mac_address);
      break;

    case i_cfg[int i].set_link_state(int ifnum, ethernet_link_state_t status, ethernet_speed_t speed):
      if (p_port_state->link_state != status) {
        p_port_state->link_state = status;
        p_port_state->link_speed = speed;
        update_client_state(rx_client_state_lp, i_rx_lp, n_rx_lp);
      }
      break;

    case i_cfg[int i].add_macaddr_filter(size_t client_num, int is_hp,
                                         ethernet_macaddr_filter_t entry) ->
                                           ethernet_macaddr_filter_result_t result:
      unsafe {
        c_macaddr_filter <: 0;
        eth_global_filter_info_t * unsafe p;
        c_macaddr_filter :> p;
        result = ethernet_add_filter_table_entry(*p, client_num, is_hp, entry);
        c_macaddr_filter <: 0;
      }
      break;

    case i_cfg[int i].del_macaddr_filter(size_t client_num, int is_hp,
                                         ethernet_macaddr_filter_t entry):
      unsafe {
        c_macaddr_filter <: 0;
        eth_global_filter_info_t * unsafe p;
        c_macaddr_filter :> p;
        ethernet_del_filter_table_entry(*p, client_num, is_hp, entry);
        c_macaddr_filter <: 0;
      }
      break;

    case i_cfg[int i].del_all_macaddr_filters(size_t client_num, int is_hp):
      unsafe {
        c_macaddr_filter <: 0;
        eth_global_filter_info_t * unsafe p;
        c_macaddr_filter :> p;
        ethernet_clear_filter_table(*p, client_num, is_hp);
        c_macaddr_filter <: 0;
      }
      break;

    case i_cfg[int i].add_ethertype_filter(size_t client_num, uint16_t ethertype):
      rx_client_state_t &client_state = rx_client_state_lp[client_num];
      size_t n = client_state.num_etype_filters;
      assert(n < ETHERNET_MAX_ETHERTYPE_FILTERS);
      client_state.etype_filters[n] = ethertype;
      client_state.num_etype_filters = n + 1;
      break;

    case i_cfg[int i].del_ethertype_filter(size_t client_num, uint16_t ethertype):
      rx_client_state_t &client_state = rx_client_state_lp[client_num];
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
      break;

    case i_cfg[int i].get_tile_id_and_timer_value(unsigned &tile_id, unsigned &time_on_tile): {
      tile_id = get_tile_id_from_chanend(c_macaddr_filter);

      timer tmr;
      tmr :> time_on_tile;
      break;
    }

    case i_cfg[int i].set_egress_qav_idle_slope(size_t ifnum, unsigned slope): {
      p_port_state->qav_idle_slope = slope;
      break;
    }

    case i_cfg[int i].set_ingress_timestamp_latency(size_t ifnum, ethernet_speed_t speed, unsigned value): {
      if (speed < 0 || speed >= NUM_ETHERNET_SPEEDS) {
        fail("Invalid Ethernet speed, must be a valid ethernet_speed_t enum value");
      }
      p_port_state->ingress_ts_latency[speed] = value / 10;
      break;
    }

    case i_cfg[int i].set_egress_timestamp_latency(size_t ifnum, ethernet_speed_t speed, unsigned value): {
      if (speed < 0 || speed >= NUM_ETHERNET_SPEEDS) {
        fail("Invalid Ethernet speed, must be a valid ethernet_speed_t enum value");
      }
      p_port_state->egress_ts_latency[speed] = value / 10;
      break;
    }

    case i_cfg[int i].enable_strip_vlan_tag(size_t client_num):
      rx_client_state_t &client_state = rx_client_state_lp[client_num];
      client_state.strip_vlan_tags = 1;
      break;

    case i_cfg[int i].disable_strip_vlan_tag(size_t client_num):
      rx_client_state_t &client_state = rx_client_state_lp[client_num];
      client_state.strip_vlan_tags = 0;
      break;

    case i_cfg[int i].enable_link_status_notification(size_t client_num):
      rx_client_state_t &client_state = rx_client_state_lp[client_num];
      client_state.status_update_state = STATUS_UPDATE_WAITING;
      break;

    case i_cfg[int i].disable_link_status_notification(size_t client_num):
      rx_client_state_t &client_state = rx_client_state_lp[client_num];
      client_state.status_update_state = STATUS_UPDATE_IGNORING;
      break;

    case i_tx_lp[int i]._init_send_packet(unsigned n, unsigned dst_port):
      if (tx_client_state_lp[i].send_buffer == null)
        tx_client_state_lp[i].requested_send_buffer_size = n;
      break;

    [[independent_guard]]
    case (int i = 0; i < n_tx_lp; i++)
      (tx_client_state_lp[i].has_outgoing_timestamp_info) =>
      i_tx_lp[i]._get_outgoing_timestamp() -> unsigned timestamp:
      timestamp = tx_client_state_lp[i].outgoing_timestamp + p_port_state->egress_ts_latency[p_port_state->link_speed];
      tx_client_state_lp[i].has_outgoing_timestamp_info = 0;
      break;

    case (!isnull(c_tx_hp) && tx_client_state_hp[0].send_buffer && !prioritize_rx) => c_tx_hp :> unsigned len:
      mii_packet_t * unsafe buf = tx_client_state_hp[0].send_buffer;
      unsigned * unsafe dptr = &buf->data[0];
      unsigned * unsafe wrap_ptr = mii_get_wrap_ptr(tx_mem_hp);
      int prewrap = ((char *) wrap_ptr - (char *) dptr);
      int len1 = prewrap > len ? len : prewrap;
      int len2 = prewrap > len ? 0 : len - prewrap;
      unsigned * unsafe start_ptr = (unsigned *) *wrap_ptr;

      // sout_char_array sends bytes in reverse order so the second
      // half must be received first
      if (len2) {
        sin_char_array(c_tx_hp, (char*)start_ptr, len2);
      }
      sin_char_array(c_tx_hp, (char*)dptr, len1);
      if (len2) {
        dptr = start_ptr + (len2+3)/4;
      }
      else {
        dptr = dptr + (len+3)/4;
      }
      buf->length = len;
      mii_commit(tx_mem_hp, dptr);
      mii_add_packet(tx_packets_hp, buf);
      buf->tcount = 0;
      tx_client_state_hp[0].send_buffer = null;
      prioritize_rx = 3;
      break;

    [[independent_guard]]
    case (int i = 0; i < n_tx_lp; i++)
      (tx_client_state_lp[i].send_buffer != null && !prioritize_rx) =>
       i_tx_lp[i]._complete_send_packet(char data[n], unsigned n,
                                     int request_timestamp,
                                     unsigned dst_port):
      mii_packet_t * unsafe buf = tx_client_state_lp[i].send_buffer;
      unsigned * unsafe dptr = &buf->data[0];
      unsigned * unsafe wrap_ptr = mii_get_wrap_ptr(tx_mem_lp);
      int prewrap = ((char *) wrap_ptr - (char *) dptr);
      int len = n;
      int len1 = prewrap > len ? len : prewrap;
      int len2 = prewrap > len ? 0 : len - prewrap;
      memcpy(dptr, data, len1);
      if (len2) {
        unsigned * unsafe start_ptr = (unsigned *) *wrap_ptr;
        memcpy((unsigned *) start_ptr, &data[len1], len2);
        dptr = start_ptr + (len2+3)/4;
      }
      else {
        dptr = dptr + (len+3)/4;
      }
      buf->length = n;
      if (request_timestamp)
        buf->timestamp_id = i+1;
      else
        buf->timestamp_id = 0;
      mii_commit(tx_mem_lp, dptr);
      mii_add_packet(tx_packets_lp, buf);
      buf->tcount = 0;
      tx_client_state_lp[i].send_buffer = null;
      tx_client_state_lp[i].requested_send_buffer_size = 0;
      prioritize_rx = 3;
      break;

    default:
      break;
    }

    if (!isnull(c_rx_hp)) {
      handle_incoming_hp_packets(rx_mem, rx_packets_hp, rd_index_hp, rx_client_state_hp[0], c_rx_hp, p_port_state);
    }

    handle_incoming_packet(rx_packets_lp, rd_index_lp, rx_client_state_lp, i_rx_lp, n_rx_lp);

    unsigned * unsafe rx_rdptr = mii_get_next_rdptr(rx_packets_lp, rx_packets_hp);

    // Keep the shared read pointer up to date
    *p_rx_rdptr = (unsigned)rx_rdptr;

    if (!isnull(c_rx_hp)) {
      // Test to see whether the buffer has reached a critical fullness level. If so, then start
      // dropping LP packets
      rx_rdptr = mii_get_rdptr(rx_packets_lp);
      mii_packet_t * unsafe packet_space = mii_reserve_at_least(rx_mem, rx_rdptr, MII_RX_THRESHOLD_BYTES);
      if (packet_space == null) {
        drop_lp_packets(rx_packets_lp, rx_client_state_lp, n_rx_lp);
      }
    }
    
    if (!isnull(c_tx_hp)) {
      if (!mii_packet_queue_full(tx_packets_hp)) {
        unsigned * unsafe rdptr = mii_get_rdptr(tx_packets_hp);
        reserve(tx_client_state_hp, 1, tx_mem_hp, rdptr);
      }
    }
    if (!mii_packet_queue_full(tx_packets_lp)) {
      unsigned * unsafe rdptr = mii_get_rdptr(tx_packets_lp);
      reserve(tx_client_state_lp, n_tx_lp, tx_mem_lp, rdptr);
    }

    handle_ts_queue(ts_queue_lp, tx_client_state_lp, n_tx_lp);
  }
}


void mii_ethernet_rt_mac(server ethernet_cfg_if i_cfg[n_cfg], static const unsigned n_cfg,
                         server ethernet_rx_if i_rx_lp[n_rx_lp], static const unsigned n_rx_lp,
                         server ethernet_tx_if i_tx_lp[n_tx_lp], static const unsigned n_tx_lp,
                         streaming chanend ? c_rx_hp,
                         streaming chanend ? c_tx_hp,
                         in port p_rxclk, in port p_rxer0, in port p_rxd0, in port p_rxdv,
                         in port p_txclk, out port p_txen, out port p_txd0,
                         clock rxclk, clock txclk,
                         static const unsigned rx_bufsize_words,
                         static const unsigned tx_bufsize_words,
                         enum ethernet_enable_shaper_t enable_shaper)
{
  in port * movable pp_rxd0 = &p_rxd0;
  in buffered port:32 * movable pp_rxd = reconfigure_port(move(pp_rxd0), in buffered port:32);
  in buffered port:32 &p_rxd = *pp_rxd;
  in port * movable pp_rxer0 = &p_rxer0;
  in buffered port:1 * movable pp_rxer = reconfigure_port(move(pp_rxer0), in buffered port:1);
  in buffered port:1 &p_rxer = *pp_rxer;
  out port * movable pp_txd0 = &p_txd0;
  out buffered port:32 * movable pp_txd = reconfigure_port(move(pp_txd0), out buffered port:32);
  out buffered port:32 &p_txd = *pp_txd;
  unsafe {
    unsigned int rx_data[rx_bufsize_words];
    unsigned int tx_data[tx_bufsize_words];
    mii_mempool_t rx_mem = mii_init_mempool(rx_data, rx_bufsize_words*4);

    // If the high priority traffic is connected then allocate half the buffer for high priority
    // and half for low priority. Otherwise, allocate it all to low priority.
    const size_t lp_buffer_bytes = !isnull(c_tx_hp) ? tx_bufsize_words * 2 : tx_bufsize_words * 4;
    const size_t hp_buffer_bytes = tx_bufsize_words * 4 - lp_buffer_bytes;
    mii_mempool_t tx_mem_lp = mii_init_mempool(tx_data, lp_buffer_bytes);
    mii_mempool_t tx_mem_hp = mii_init_mempool(tx_data + (lp_buffer_bytes/4), hp_buffer_bytes);

    packet_queue_info_t rx_packets_lp, rx_packets_hp, tx_packets_lp, tx_packets_hp, incoming_packets;
    mii_init_packet_queue((mii_packet_queue_t)&rx_packets_lp);
    mii_init_packet_queue((mii_packet_queue_t)&rx_packets_hp);
    mii_init_packet_queue((mii_packet_queue_t)&tx_packets_lp);
    mii_init_packet_queue((mii_packet_queue_t)&tx_packets_hp);
    mii_init_packet_queue((mii_packet_queue_t)&incoming_packets);

    // Shared read pointer to help optimize the RX code
    unsigned rx_rdptr = 0;
    unsigned * unsafe p_rx_rdptr = &rx_rdptr;

    mii_init_lock();
    mii_ts_queue_entry_t ts_fifo[MII_TIMESTAMP_QUEUE_MAX_SIZE + 1];
    mii_ts_queue_info_t ts_queue_info;

    if (n_tx_lp > MII_TIMESTAMP_QUEUE_MAX_SIZE) {
      fail("Exceeded maximum number of transmit clients. Increase MII_TIMESTAMP_QUEUE_MAX_SIZE in ethernet_conf.h");
    }

    if (!ETHERNET_SUPPORT_HP_QUEUES && (!isnull(c_rx_hp) || !isnull(c_tx_hp))) {
      fail("Using high priority channels without #define ETHERNET_SUPPORT_HP_QUEUES set true");
    }

    mii_ts_queue_t ts_queue = mii_ts_queue_init(&ts_queue_info, ts_fifo, n_tx_lp + 1);
    streaming chan c;
    mii_master_init(p_rxclk, p_rxd, p_rxdv, rxclk, p_txclk, p_txen, p_txd, txclk, p_rxer);

    ethernet_port_state_t port_state;
    init_server_port_state(port_state, enable_shaper == ETHERNET_ENABLE_SHAPER);

    ethernet_port_state_t * unsafe p_port_state = (ethernet_port_state_t * unsafe)&port_state;

    chan c_conf;
    par {
      mii_master_rx_pins(rx_mem,
                         (mii_packet_queue_t)&incoming_packets,
                         p_rx_rdptr,
                         p_rxdv, p_rxd, p_rxer, c);

      mii_master_tx_pins(tx_mem_lp,
                         tx_mem_hp,
                         (mii_packet_queue_t)&tx_packets_lp,
                         (mii_packet_queue_t)&tx_packets_hp,
                         ts_queue, p_txd,
                         p_port_state);

      mii_ethernet_filter(c, c_conf,
                          (mii_packet_queue_t)&incoming_packets,
                          (mii_packet_queue_t)&rx_packets_lp,
                          (mii_packet_queue_t)&rx_packets_hp);

      mii_ethernet_server(rx_mem,
                          (mii_packet_queue_t)&rx_packets_lp,
                          (mii_packet_queue_t)&rx_packets_hp,
                          p_rx_rdptr,
                          tx_mem_lp,
                          tx_mem_hp,
                          (mii_packet_queue_t)&tx_packets_lp,
                          (mii_packet_queue_t)&tx_packets_hp,
                          ts_queue,
                          i_cfg, n_cfg,
                          i_rx_lp, n_rx_lp,
                          i_tx_lp, n_tx_lp,
                          c_rx_hp,
                          c_tx_hp,
                          c_conf,
                          p_port_state);
    }
  }
}

