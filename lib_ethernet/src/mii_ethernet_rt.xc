#include <string.h>

#include "ethernet.h"
#include "mii_master.h"
#include "mii_filter.h"
#include "mii_buffering.h"
#include "mii_ts_queue.h"
#include "client_state.h"
#define DEBUG_UNIT ETHERNET_CLIENT_HANDLER
#include "debug_print.h"
#include "xassert.h"
#include "print.h"

unsafe static void reserve(tx_client_state_t client_state[n], unsigned n, mii_mempool_t mem)
{
  for (int i = 0; i < n; i++) {
    if (client_state[i].requested_send_buffer_size != 0 &&
        client_state[i].send_buffer == null) {
      debug_printf("Trying to reserve send buffer (client %d, size %d)\n",
                   i,
                   client_state[i].requested_send_buffer_size);
      client_state[i].send_buffer =
        mii_reserve_at_least(mem, client_state[i].requested_send_buffer_size);
    }
  }
}

unsafe static void handle_incoming_packet(mii_mempool_t rx_mem,
                                          mii_rdptr_t &rdptr,
                                          rx_client_state_t client_state[n],
                                          server ethernet_rx_if i_rx[n],
                                          unsigned n, int is_hp)
{
  mii_packet_t * unsafe buf = mii_get_my_next_buf(rx_mem, rdptr);
  if (!buf || buf->stage != MII_STAGE_FILTERED)
    return;

  rdptr = mii_update_my_rdptr(rx_mem, rdptr);

  int tcount = 0;
  if (buf->filter_result && (is_hp == ethernet_filter_result_is_hp(buf->filter_result))) {
    debug_printf("Assigning packet to clients (filter result %x)\n",
                 buf->filter_result);
    for (int i = 0; i < n; i++) {
      int client_wants_packet = ((buf->filter_result >> i) & 1);
      if (client_state[i].num_etype_filters != 0) {
        char * unsafe data = (char * unsafe) buf->data;
        int passed_etype_filter = 0;
        uint16_t etype = ((uint16_t) data[12] << 8) + data[13];
        int qhdr = (etype == 0x8100);
        if (qhdr) {
          // has a 802.1q tag - read etype from next word
          etype = ((uint16_t) data[16] << 8) + data[17];
        }
        for (int j = 0; j < client_state[i].num_etype_filters; j++) {
          if (client_state[i].etype_filters[j] == etype) {
            passed_etype_filter = 1;
            break;
          }
        }
        client_wants_packet &= passed_etype_filter;
      }
      if (client_wants_packet) {
        debug_printf("Trying to queue for client %d\n", i);
        int wrptr = client_state[i].wrIndex;
        int new_wrptr = wrptr + 1;
        if (new_wrptr >= ETHERNET_RX_CLIENT_QUEUE_SIZE) {
          new_wrptr = 0;
        }
        if (new_wrptr != client_state[i].rdIndex) {
          debug_printf("Putting in client queue %d\n", i);
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

  if (tcount == 0) {
    mii_free(buf);
  }
  else {
    buf->tcount = tcount - 1;
  }
}

unsafe static void handle_incoming_hp_packets(mii_mempool_t rx_mem,
                                              mii_rdptr_t &rdptr,
                                              rx_client_state_t &client_state,
                                              streaming chanend c_rx_hp)
{
  while (1) {
    mii_packet_t * unsafe buf = mii_get_my_next_buf(rx_mem, rdptr);
    if (!buf || buf->stage != MII_STAGE_FILTERED)
      return;

    rdptr = mii_update_my_rdptr(rx_mem, rdptr);

    int client_wants_packet = 0;
    if (buf->filter_result && ethernet_filter_result_is_hp(buf->filter_result)) {

      int client_wants_packet = (buf->filter_result & 1);

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
    }

    if (client_wants_packet == 0) {
      mii_free(buf);
      continue;
    }

    ethernet_packet_info_t info;
    info.type = ETH_DATA;
    info.src_ifnum = buf->src_port;
    info.timestamp = buf->timestamp;
    info.len = buf->length;
    info.filter_data = buf->filter_data;
    sout_char_array(c_rx_hp, (char *)&info, sizeof(info));
    int len = buf->length;
    unsigned * unsafe wrap_ptr = mii_packet_get_wrap_ptr(buf);
    unsigned * unsafe dptr = buf->data;
    int prewrap = ((char *) wrap_ptr - (char *) dptr);
    int len1 = prewrap > len ? len : prewrap;
    int len2 = prewrap > len ? 0 : len - prewrap;
    sout_char_array(c_rx_hp, (char *)dptr, len1);
    if (len2) {
      sout_char_array(c_rx_hp, (char *)dptr, len2);
    }
    mii_free(buf);
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
  mii_packet_t * unsafe buf = mii_ts_queue_get_entry(ts_queue);
  if (buf) {
    unsigned index = buf->timestamp_id - 1;
    client_state[index].has_outgoing_timestamp_info = 1;
    client_state[index].outgoing_timestamp = buf->timestamp;

    if (mii_get_and_dec_transmit_count(buf) == 0)
      mii_free(buf);
  }
}

unsafe static void mii_ethernet_server_aux(mii_mempool_t rx_hp_mem,
                                           mii_mempool_t rx_lp_mem,
                                           mii_mempool_t tx_hp_mem,
                                           mii_mempool_t tx_lp_mem,
                                           mii_ts_queue_t ts_queue_lp,
                                           server ethernet_cfg_if i_cfg[n_cfg], static const unsigned n_cfg,
                                           server ethernet_rx_if i_rx_lp[n_rx_lp], static const unsigned n_rx_lp,
                                           server ethernet_tx_if i_tx_lp[n_tx_lp], static const unsigned n_tx_lp,
                                           streaming chanend ? c_rx_hp,
                                           streaming chanend ? c_tx_hp,
                                           chanend c_macaddr_filter)
{
  char mac_address[6] = {0};
  ethernet_link_state_t link_status = ETHERNET_LINK_DOWN;
  rx_client_state_t rx_client_state_lp[n_rx_lp];
  rx_client_state_t rx_client_state_hp[1];
  tx_client_state_t tx_client_state_lp[n_tx_lp];
  tx_client_state_t tx_client_state_hp[1];
  mii_rdptr_t rdptr_hp, rdptr_lp;

  if (rx_hp_mem) {
    rdptr_hp = mii_init_my_rdptr(rx_hp_mem);
  }
  rdptr_lp = mii_init_my_rdptr(rx_lp_mem);

  init_rx_client_state(rx_client_state_lp, n_rx_lp);
  init_rx_client_state(rx_client_state_hp, 1);
  init_tx_client_state(tx_client_state_lp, n_tx_lp);
  init_tx_client_state(tx_client_state_hp, 1);

  tx_client_state_hp[0].requested_send_buffer_size = ETHERNET_MAX_PACKET_SIZE;

  int prioritize_rx = 0;
  while (1) {
    if (prioritize_rx)
      prioritize_rx--;

    select {
    case i_rx_lp[int i].get_index() -> size_t result:
      result = i;
      break;

    case i_rx_lp[int i].get_packet(ethernet_packet_info_t &desc, char data[n], unsigned n):
      prioritize_rx += 1;
      if (rx_client_state_lp[i].status_update_state == STATUS_UPDATE_PENDING) {
        data[0] = 1;
        data[1] = link_status;
        desc.type = ETH_IF_STATUS;
        rx_client_state_lp[i].status_update_state = STATUS_UPDATE_WAITING;
      }
      else if (rx_client_state_lp[i].rdIndex != rx_client_state_lp[i].wrIndex) {
        int rdIndex = rx_client_state_lp[i].rdIndex;
        mii_packet_t * unsafe buf = rx_client_state_lp[i].fifo[rdIndex];
        ethernet_packet_info_t info;
        info.type = ETH_DATA;
        info.src_ifnum = buf->src_port;
        info.timestamp = buf->timestamp;
        info.len = buf->length;
        info.filter_data = buf->filter_data;
        memcpy(&desc, &info, sizeof(info));
        int len = (n > buf->length ? buf->length : n);
        unsigned * unsafe wrap_ptr = mii_packet_get_wrap_ptr(buf);
        unsigned * unsafe dptr = buf->data;
        int prewrap = ((char *) wrap_ptr - (char *) dptr);
        int len1 = prewrap > len ? len : prewrap;
        int len2 = prewrap > len ? 0 : len - prewrap;
        memcpy(data, dptr, len1);
        if (len2) {
          memcpy(&data[len1], (unsigned *) *wrap_ptr, len2);
        }
        if (mii_get_and_dec_transmit_count(buf) == 0) {
          mii_free(buf);
        }
        if (rdIndex == ETHERNET_RX_CLIENT_QUEUE_SIZE - 1) {
          rx_client_state_lp[i].rdIndex = 0;
        }
        else {
          rx_client_state_lp[i].rdIndex++;
        }

        if (rx_client_state_lp[i].rdIndex != rx_client_state_lp[i].wrIndex) {
          i_rx_lp[i].packet_ready();
        }
      } else {
        desc.type = ETH_NO_DATA;
      }
      break;

    case i_cfg[int i].get_macaddr(size_t ifnum, char r_mac_address[6]):
      memcpy(r_mac_address, mac_address, 6);
      break;

    case i_cfg[int i].set_macaddr(size_t ifnum, char r_mac_address[6]):
      memcpy(mac_address, r_mac_address, 6);
      break;

    case i_cfg[int i].set_link_state(int ifnum, ethernet_link_state_t status):
      if (link_status != status) {
        link_status = status;
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

    case i_cfg[int i].add_ethertype_filter(size_t client_num, int is_hp, uint16_t ethertype):
      rx_client_state_t &client_state = is_hp ? rx_client_state_hp[client_num] : rx_client_state_lp[client_num];
      size_t n = client_state.num_etype_filters;
      assert(n < ETHERNET_MAX_ETHERTYPE_FILTERS);
      client_state.etype_filters[n] = ethertype;
      client_state.num_etype_filters = n + 1;
      break;

    case i_cfg[int i].del_ethertype_filter(size_t client_num, int is_hp, uint16_t ethertype):
      rx_client_state_t &client_state = is_hp ? rx_client_state_hp[client_num] : rx_client_state_lp[client_num];
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

    case i_tx_lp[int i]._init_send_packet(unsigned n, unsigned dst_port):
      if (tx_client_state_lp[i].send_buffer == null)
        tx_client_state_lp[i].requested_send_buffer_size = n + sizeof(mii_packet_t);
      break;

    [[independent_guard]]
    case (int i = 0; i < n_tx_lp; i++)
      (tx_client_state_lp[i].has_outgoing_timestamp_info) =>
      i_tx_lp[i]._get_outgoing_timestamp() -> unsigned timestamp:
      timestamp = tx_client_state_lp[i].outgoing_timestamp;
      tx_client_state_lp[i].has_outgoing_timestamp_info = 0;
      break;

    case (tx_client_state_hp[0].send_buffer && !prioritize_rx) => c_tx_hp :> unsigned len:
      mii_packet_t * unsafe buf = tx_client_state_hp[0].send_buffer;
      unsigned * unsafe dptr = &buf->data[0];
      unsigned * unsafe wrap_ptr = mii_packet_get_wrap_ptr(buf);
      int prewrap = ((char *) wrap_ptr - (char *) dptr);
      int len1 = prewrap > len ? len : prewrap;
      int len2 = prewrap > len ? 0 : len - prewrap;
      sin_char_array(c_tx_hp, (char*)dptr, len1);
      if (len2) {
        unsigned * unsafe start_ptr = (unsigned *) *wrap_ptr;
        sin_char_array(c_tx_hp, (char*)start_ptr, len2);
        dptr = start_ptr + (len2+3)/4;
      }
      else {
        dptr = dptr + (len+3)/4;
      }
      buf->length = len;
      mii_commit(buf, dptr);
      buf->tcount = 0;
      buf->stage = 1;
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
      unsigned * unsafe wrap_ptr = mii_packet_get_wrap_ptr(buf);
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
      mii_commit(buf, dptr);
      buf->tcount = 0;
      buf->stage = 1;
      tx_client_state_lp[i].send_buffer = null;
      tx_client_state_lp[i].requested_send_buffer_size = 0;
      prioritize_rx = 3;
      break;

    default:
      break;
    }

    if (rx_hp_mem) {
      handle_incoming_hp_packets(rx_hp_mem, rdptr_hp, rx_client_state_hp[0], c_rx_hp);
    }

    handle_incoming_packet(rx_lp_mem, rdptr_lp, rx_client_state_lp, i_rx_lp, n_rx_lp, 0);

    if (tx_hp_mem) {
      reserve(tx_client_state_hp, 1, tx_hp_mem);
    }
    reserve(tx_client_state_lp, n_tx_lp, tx_lp_mem);

    handle_ts_queue(ts_queue_lp, tx_client_state_lp, n_tx_lp);
  }
}


void mii_ethernet_rt(server ethernet_cfg_if i_cfg[n_cfg], static const unsigned n_cfg,
                     server ethernet_rx_if i_rx_lp[n_rx_lp], static const unsigned n_rx_lp,
                     server ethernet_tx_if i_tx_lp[n_tx_lp], static const unsigned n_tx_lp,
                     streaming chanend ? c_rx_hp,
                     streaming chanend ? c_tx_hp,
                      in port p_rxclk, in port p_rxer0, in port p_rxd0, in port p_rxdv,
                     in port p_txclk, out port p_txen, out port p_txd0,
                     clock rxclk, clock txclk,
                     static const unsigned rx_bufsize_words,
                     static const unsigned tx_bufsize_words,
                     static const unsigned rx_hp_bufsize_words,
                     static const unsigned tx_hp_bufsize_words,
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
    unsigned int rx_lp_data[rx_bufsize_words];
    unsigned int tx_lp_data[tx_bufsize_words];
    unsigned int rx_hp_data[rx_hp_bufsize_words];
    unsigned int tx_hp_data[tx_hp_bufsize_words];
    mii_mempool_t rx_lp_mem = mii_init_mempool(rx_lp_data, rx_bufsize_words*4);
    mii_mempool_t rx_hp_mem = mii_init_mempool(rx_hp_data, rx_hp_bufsize_words*4);
    mii_mempool_t tx_hp_mem = mii_init_mempool(tx_hp_data, tx_bufsize_words*4);
    mii_mempool_t tx_lp_mem = mii_init_mempool(tx_lp_data, tx_hp_bufsize_words*4);
    mii_init_lock();
    unsigned ts_fifo_lp[n_rx_lp];
    mii_ts_queue_info_t ts_queue_info_lp;
    mii_ts_queue_t ts_queue_lp = mii_ts_queue_init(&ts_queue_info_lp, ts_fifo_lp, n_tx_lp);
    streaming chan c;
    mii_master_init(p_rxclk, p_rxd, p_rxdv, rxclk, p_txclk, p_txen, p_txd, txclk);

    if (!ETHERNET_SUPPORT_HP_QUEUES || isnull(c_rx_hp)) {
      rx_hp_mem = 0;
    }
    if (!ETHERNET_SUPPORT_HP_QUEUES || isnull(c_tx_hp)) {
      tx_hp_mem = 0;
    }

    int idle_slope = (11<<MII_CREDIT_FRACTIONAL_BITS);
    chan c_conf;
    par {
        mii_master_rx_pins(rx_hp_mem, rx_lp_mem,
                           p_rxdv, p_rxd, p_rxer, c);
        mii_master_tx_pins(tx_hp_mem, tx_lp_mem, ts_queue_lp, p_txd,
                           enable_shaper == ETHERNET_ENABLE_SHAPER, &idle_slope);
        mii_ethernet_filter(c, c_conf);
        mii_ethernet_server_aux(rx_hp_mem, rx_lp_mem,
                                tx_hp_mem, tx_lp_mem,
                                ts_queue_lp,
                                i_cfg, n_cfg,
                                i_rx_lp, n_rx_lp,
                                i_tx_lp, n_tx_lp,
                                c_rx_hp,
                                c_tx_hp,
                                c_conf);
    }
  }
}

