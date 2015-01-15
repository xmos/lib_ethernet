#include "ethernet.h"
#include "mii_master.h"
#include "mii_filter.h"
#include "mii_buffering.h"
#include "mii_ts_queue.h"
#include "string.h"
#define DEBUG_UNIT ETHERNET_CLIENT_HANDLER
#include "debug_print.h"
#include "xassert.h"

enum status_update_state_t {
  STATUS_UPDATE_IGNORING,
  STATUS_UPDATE_WAITING,
  STATUS_UPDATE_PENDING,
};

// data structure to keep track of link layer status.
typedef struct
{
  unsigned dropped_pkt_cnt;
  int rdIndex;
  int wrIndex;
  mii_packet_t * unsafe fifo[ETHERNET_RX_CLIENT_QUEUE_SIZE];
  int status_update_state;
  int requested_send_buffer_size;
  int requested_send_priority;
  mii_packet_t * unsafe send_buffer;
  int has_outgoing_timestamp_info;
  unsigned outgoing_timestamp;
  size_t num_etype_filters;
  uint16_t etype_filters[ETHERNET_MAX_ETHERTYPE_FILTERS];
} client_state_t;


unsafe static void handle_incoming_packet(mii_mempool_t rx_mem,
                                          mii_rdptr_t &rdptr,
                                          client_state_t client_info[n],
                                          server ethernet_if i_eth[n],
                                          unsigned n)
{
  mii_packet_t * unsafe buf = mii_get_my_next_buf(rx_mem, rdptr);
  if (!buf || buf->stage != 1)
    return;

  rdptr = mii_update_my_rdptr(rx_mem, rdptr);

  int tcount = 0;
  if (buf->filter_result) {
    debug_printf("Assigning packet to clients (filter result %x)\n",
                 buf->filter_result);
    for (int i = 0; i < n; i++) {
      int client_wants_packet = ((buf->filter_result >> i) & 1);
      if (client_info[i].num_etype_filters != 0) {
        char * unsafe data = (char * unsafe) buf->data;
        int passed_etype_filter = 0;
        uint16_t etype = ((uint16_t) data[12] << 8) + data[13];
        int qhdr = (etype == 0x8100);
        if (qhdr) {
          // has a 802.1q tag - read etype from next word
          etype = ((uint16_t) data[16] << 8) + data[17];
        }
        for (int j = 0; j < client_info[i].num_etype_filters; j++) {
          if (client_info[i].etype_filters[j] == etype) {
            passed_etype_filter = 1;
            break;
          }
        }
        client_wants_packet &= passed_etype_filter;
      }
      if (client_wants_packet) {
        debug_printf("Trying to queue for client %d\n", i);
        int wrptr = client_info[i].wrIndex;
        int new_wrptr = wrptr + 1;
        if (new_wrptr >= ETHERNET_RX_CLIENT_QUEUE_SIZE) {
          new_wrptr = 0;
        }
        if (new_wrptr != client_info[i].rdIndex) {
          debug_printf("Putting in client queue %d\n", i);
          client_info[i].fifo[wrptr] = buf;
          tcount++;
          i_eth[i].packet_ready();
          client_info[i].wrIndex = new_wrptr;
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

unsafe static void mii_ethernet_server_aux(mii_mempool_t rx_hp_mem,
                                           mii_mempool_t rx_lp_mem,
                                           mii_mempool_t tx_hp_mem,
                                           mii_mempool_t tx_lp_mem,
                                           mii_ts_queue_t ts_queue,
                                           server ethernet_if i_eth[n],
                                           static const unsigned n,
                                           chanend c_macaddr_filter)
{
  char mac_address[6] = {0};
  ethernet_link_state_t link_status = ETHERNET_LINK_DOWN;
  client_state_t client_info[n];
  mii_rdptr_t rdptr_hp, rdptr_lp;

  if (rx_hp_mem) {
    rdptr_hp = mii_init_my_rdptr(rx_hp_mem);
  }
  rdptr_lp = mii_init_my_rdptr(rx_lp_mem);

  for (int i = 0; i < n; i ++) {
    client_info[i].dropped_pkt_cnt = 0;
    client_info[i].rdIndex = 0;
    client_info[i].wrIndex = 0;
    client_info[i].status_update_state = STATUS_UPDATE_IGNORING;
    client_info[i].requested_send_buffer_size = 0;
    client_info[i].send_buffer = null;
    client_info[i].has_outgoing_timestamp_info = 0;
    client_info[i].num_etype_filters = 0;
  }

  int prioritize_rx = 0;
  while (1) {
    if (prioritize_rx)
      prioritize_rx--;

    select {
    case i_eth[int i].get_packet(ethernet_packet_info_t &desc,
                                 char data[n],
                                 unsigned n):
      prioritize_rx += 1;
      if (client_info[i].status_update_state == STATUS_UPDATE_PENDING) {
        data[0] = 1;
        data[1] = link_status;
        desc.type = ETH_IF_STATUS;
        client_info[i].status_update_state = STATUS_UPDATE_WAITING;
      }
      else if (client_info[i].rdIndex != client_info[i].wrIndex) {
        // send received packet
        int rdIndex = client_info[i].rdIndex;
        mii_packet_t * unsafe buf = client_info[i].fifo[rdIndex];
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
          client_info[i].rdIndex = 0;
        }
        else {
          client_info[i].rdIndex++;
        }

        if (client_info[i].rdIndex != client_info[i].wrIndex) {
          i_eth[i].packet_ready();
        }
      } else {
        desc.type = ETH_NO_DATA;
      }
      break;
    case i_eth[int i].get_macaddr(size_t ifnum, char r_mac_address[6]):
      memcpy(r_mac_address, mac_address, 6);
      break;
    case i_eth[int i].set_macaddr(size_t ifnum, char r_mac_address[6]):
      memcpy(mac_address, r_mac_address, 6);
      break;
    case i_eth[int i].add_macaddr_filter(ethernet_macaddr_filter_t entry) -> ethernet_macaddr_filter_result_t result:
      unsafe {
        c_macaddr_filter <: 0;
        eth_global_filter_info_t * unsafe p;
        c_macaddr_filter :> p;
        result = ethernet_add_filter_table_entry(*p, i, entry);
        c_macaddr_filter <: 0;
      }
      break;
    case i_eth[int i].del_macaddr_filter(ethernet_macaddr_filter_t entry):
      unsafe {
        c_macaddr_filter <: 0;
        eth_global_filter_info_t * unsafe p;
        c_macaddr_filter :> p;
        ethernet_del_filter_table_entry(*p, i, entry);
        c_macaddr_filter <: 0;
      }
      break;
    case i_eth[int i].del_all_macaddr_filters():
      unsafe {
        c_macaddr_filter <: 0;
        eth_global_filter_info_t * unsafe p;
        c_macaddr_filter :> p;
        ethernet_clear_filter_table(*p, i);
        c_macaddr_filter <: 0;
      }
      break;
    case i_eth[int i].add_ethertype_filter(uint16_t ethertype):
      size_t n = client_info[i].num_etype_filters;
      assert(n < ETHERNET_MAX_ETHERTYPE_FILTERS);
      client_info[i].etype_filters[n] = ethertype;
      client_info[i].num_etype_filters = n + 1;
      break;
    case i_eth[int i].del_ethertype_filter(uint16_t ethertype):
      size_t j = 0;
      size_t n = client_info[i].num_etype_filters;
      while (j < n) {
        if (client_info[i].etype_filters[j] == ethertype) {
          client_info[i].etype_filters[j] = client_info[i].etype_filters[n-1];
          n--;
        }
        else {
          j++;
        }
      }
      client_info[i].num_etype_filters = n;
      break;
    case i_eth[int i]._init_send_packet(unsigned n, int is_high_priority,
                                       unsigned dst_port):
      if (client_info[i].send_buffer == null)
        client_info[i].requested_send_buffer_size = n + sizeof(mii_packet_t);
      if (tx_hp_mem)
        client_info[i].requested_send_priority = is_high_priority;
      break;

    [[independent_guard]]
    case (int i = 0; i < n; i++)
      (client_info[i].has_outgoing_timestamp_info) =>
      i_eth[i]._get_outgoing_timestamp() -> unsigned timestamp:
      timestamp = client_info[i].outgoing_timestamp;
      client_info[i].has_outgoing_timestamp_info = 0;
      break;

    [[independent_guard]]
    case (int i = 0; i < n; i++)
      (client_info[i].send_buffer != null && !prioritize_rx) =>
       i_eth[i]._complete_send_packet(char data[n], unsigned n,
                                     int request_timestamp,
                                     unsigned dst_port):
      mii_packet_t * unsafe buf = client_info[i].send_buffer;
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
      client_info[i].send_buffer = null;
      client_info[i].requested_send_buffer_size = 0;
      prioritize_rx = 3;
      break;

    case i_eth[int i].set_link_state(int ifnum, ethernet_link_state_t status):
      if (link_status != status) {
        link_status = status;
        for (int i = 0; i < n; i+=1) {
          if (client_info[i].status_update_state == STATUS_UPDATE_WAITING) {
            client_info[i].status_update_state = STATUS_UPDATE_PENDING;
            i_eth[i].packet_ready();
          }
        }
      }
      break;
    default:
      break;
    }

    if (rx_hp_mem)
      handle_incoming_packet(rx_hp_mem, rdptr_hp, client_info, i_eth, n);

    handle_incoming_packet(rx_lp_mem, rdptr_lp, client_info, i_eth, n);

    for (int i = 0; i < n; i++) {
      if (client_info[i].requested_send_buffer_size != 0 &&
          client_info[i].send_buffer == null) {
        debug_printf("Trying to reserve send buffer (client %d, size %d)\n",
                     i,
                     client_info[i].requested_send_buffer_size);
        int is_hp = (tx_hp_mem &&
                     client_info[i].requested_send_priority);
        mii_mempool_t mem = is_hp ? tx_hp_mem : tx_lp_mem;
        client_info[i].send_buffer =
          mii_reserve_at_least(mem, client_info[i].requested_send_buffer_size);
      }
    }

    mii_packet_t * unsafe buf = mii_ts_queue_get_entry(ts_queue);
    if (buf) {
      client_info[buf->timestamp_id - 1].has_outgoing_timestamp_info = 1;
      client_info[buf->timestamp_id - 1].outgoing_timestamp = buf->timestamp;
      if (mii_get_and_dec_transmit_count(buf) == 0)
        mii_free(buf);
    }
  }
}


void mii_ethernet_rt(server ethernet_if i_eth[n], static const unsigned n,
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
  unsigned ts_fifo[n];
  mii_ts_queue_info_t ts_queue_info;
  mii_ts_queue_t ts_queue = mii_ts_queue_init(&ts_queue_info, ts_fifo, n);
  streaming chan c;
  mii_master_init(p_rxclk, p_rxd, p_rxdv, rxclk, p_txclk, p_txen, p_txd, txclk);
  if (!ETHERNET_SUPPORT_HP_QUEUES) {
    rx_hp_mem = tx_hp_mem = 0;
  }
  int idle_slope = (11<<MII_CREDIT_FRACTIONAL_BITS);
  chan c_conf;
  par {
      mii_master_rx_pins(rx_hp_mem, rx_lp_mem,
                         p_rxdv, p_rxd, p_rxer, c);
      mii_master_tx_pins(tx_hp_mem, tx_lp_mem, ts_queue, p_txd,
                         enable_shaper == ETHERNET_ENABLE_SHAPER, &idle_slope);
      mii_ethernet_filter(c, c_conf);
      mii_ethernet_server_aux(rx_hp_mem, rx_lp_mem,
                              tx_hp_mem, tx_lp_mem, ts_queue,
                              i_eth, n, c_conf);
  }
  }
}

