#include "ethernet.h"
#include "mii_master.h"
#include "mii_lite_driver.h"
#include "debug_print.h"
#include "string.h"
#include "xs1.h"
#include "xassert.h"
#include "macaddr_filter.h"
#include "print.h"

#ifndef ETHERNET_MAC_PROMISCUOUS
#define ETHERNET_MAC_PROMISCUOUS 0
#endif

enum status_update_state_t {
  STATUS_UPDATE_IGNORING,
  STATUS_UPDATE_WAITING,
  STATUS_UPDATE_PENDING,
};

// data structure to keep track of link layer status.
typedef struct
{
  int status_update_state;
  int incoming_packet;
  size_t num_etype_filters;
  uint16_t etype_filters[ETHERNET_MAX_ETHERTYPE_FILTERS];
} client_state_t;

static unsafe inline int is_broadcast(char * unsafe buf)
{
  return (buf[0] & 0x1);
}

static unsafe inline int compare_mac(char * unsafe buf,
                                     const char mac[6])
{
  for (int i=0; i<6;i++)
    if (buf[i] != mac[i])
      return 0;
  return 1;
}

static unsafe void mii_ethernet_lite_aux(chanend c_in, chanend c_out,
                                         chanend notifications,
                                         server ethernet_if i_eth[n],
                                         static const unsigned n,
                                         static const unsigned double_rx_bufsize_words)
{
  char mac_address[6] = {0};
  ethernet_link_state_t link_status = ETHERNET_LINK_DOWN;
  client_state_t client_info[n];
  int rxbuf[double_rx_bufsize_words];
  int txbuf[(ETHERNET_MAX_PACKET_SIZE+3)/4];
  struct mii_lite_data_t mii_lite_data;
  int incoming_nbytes;
  int incoming_timestamp;
  int incoming_tcount;
  unsigned incoming_appdata;
  char * unsafe incoming_data = null;
  eth_global_filter_info_t filter_info;

  for (int i = 0; i < n; i ++) {
    client_info[i].status_update_state = STATUS_UPDATE_IGNORING;
    client_info[i].incoming_packet = 0;
    client_info[i].num_etype_filters = 0;
  }

  ethernet_init_filter_table(filter_info);

  // Setup buffering and interrupt for packet handling
  mii_lite_buffer_init(mii_lite_data, c_in, notifications,
                       rxbuf, double_rx_bufsize_words);
  mii_lite_out_init(c_out);

  while (1) {
    select {
    case i_eth[int i].get_packet(ethernet_packet_info_t &desc,
                                 char data[n],
                                 unsigned n):
      if (client_info[i].status_update_state == STATUS_UPDATE_PENDING) {
        data[0] = 1;
        data[1] = link_status;
        desc.type = ETH_IF_STATUS;
        client_info[i].status_update_state = STATUS_UPDATE_WAITING;
      } else if (client_info[i].incoming_packet) {
        desc.type = ETH_DATA;
        desc.timestamp = incoming_timestamp;
        desc.src_ifnum = 0;
        desc.filter_data = 0;
        desc.len = incoming_nbytes;
        memcpy(data, incoming_data, incoming_nbytes);
        client_info[i].incoming_packet = 0;
        incoming_tcount--;
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
      result = ethernet_add_filter_table_entry(filter_info, i, entry);
      break;
    case i_eth[int i].del_macaddr_filter(ethernet_macaddr_filter_t entry):
      ethernet_del_filter_table_entry(filter_info, i, entry);
      break;
    case i_eth[int i].del_all_macaddr_filters():
      ethernet_clear_filter_table(filter_info, i);
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
      // Do nothing
      break;

    case i_eth[int i]._get_outgoing_timestamp() -> unsigned timestamp:
      fail("Outgoing timestamps are not supported in mii ethernet lite");
      break;

    case i_eth[int i]._complete_send_packet(char data[n], unsigned n,
                                           int request_timestamp,
                                           unsigned dst_port):
      memcpy(txbuf, data, n);
      mii_lite_out_packet(c_out, txbuf, 0, n);
      mii_lite_out_packet_done(c_out);
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
    case inuchar_byref(notifications, mii_lite_data.notifySeen):
      break;
    default:
      break;
    }
    // Check that there is an incoming packet
    if (!incoming_data) {
      char * unsafe data;
      int nbytes;
      unsigned timestamp;
      {data, nbytes, timestamp} = mii_lite_get_in_buffer(mii_lite_data);
      if (data) {
        unsigned appdata;
        incoming_timestamp = timestamp;
        incoming_nbytes = nbytes;
        incoming_data = data;
        incoming_tcount = 0;
        int filter_result =
          ethernet_do_filtering(filter_info, (char *) data, nbytes,
                                incoming_appdata);
        for (int i = 0; i < n; i++) {
          int client_wants_packet = ((filter_result >> i) & 1);
          if (client_info[i].num_etype_filters != 0) {
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
            client_info[i].incoming_packet = 1;
            i_eth[i].packet_ready();
            incoming_tcount++;
          }
        }
      }
    }

    if (incoming_data != null && incoming_tcount == 0) {
      mii_lite_free_in_buffer(mii_lite_data, incoming_data);
      incoming_data = null;
    }
  }
}


void mii_ethernet(server ethernet_if i_eth[n],
                  static const unsigned n,
                  in port p_rxclk, in port p_rxer, in port p_rxd0,
                  in port p_rxdv,
                  in port p_txclk, out port p_txen, out port p_txd0,
                  port p_timing,
                  clock rxclk,
                  clock txclk,
                  static const unsigned double_rx_bufsize_words)

{
  in port * movable pp_rxd0 = &p_rxd0;
  in buffered port:32 * movable pp_rxd = reconfigure_port(move(pp_rxd0), in buffered port:32);
  in buffered port:32 &p_rxd = *pp_rxd;
  out port * movable pp_txd0 = &p_txd0;
  out buffered port:32 * movable pp_txd = reconfigure_port(move(pp_txd0), out buffered port:32);
  out buffered port:32 &p_txd = *pp_txd;
  mii_master_init(p_rxclk, p_rxd, p_rxdv, rxclk, p_txclk, p_txen, p_txd, txclk);
  chan c_in, c_out;
  chan notifications;
  unsafe {
    par {
      {asm(""::"r"(notifications));mii_lite_driver(p_rxd, p_rxdv, p_txd, p_timing,
                                                   c_in, c_out);}
      mii_ethernet_lite_aux(c_in, c_out, notifications,
                            i_eth, n, double_rx_bufsize_words);
    }
  }
}
