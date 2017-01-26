// Copyright (c) 2015-2017, XMOS Ltd, All rights reserved
#include "ethernet.h"
#include "default_ethernet_conf.h"
#include "mii_master.h"
#include "mii_lite_driver.h"
#include "debug_print.h"
#include "string.h"
#include "xs1.h"
#include "xassert.h"
#include "macaddr_filter.h"
#include "print.h"
#include "ntoh.h"
#include "mii.h"

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
                                     const char mac[MACADDR_NUM_BYTES])
{
  for (int i = 0; i < MACADDR_NUM_BYTES; i++) {
    if (buf[i] != mac[i])
      return 0;
  }
  return 1;
}

static unsafe inline void init_client_state(client_state_t client_state[n], static const unsigned n)
{
  for (int i = 0; i < n; i ++) {
    client_state[i].status_update_state = STATUS_UPDATE_IGNORING;
    client_state[i].incoming_packet = 0;
    client_state[i].num_etype_filters = 0;
  }
}

static unsafe inline void update_client_state(client_state_t client_state[n], server ethernet_rx_if i_rx[n],
                                              static const unsigned n)
{
  for (int i = 0; i < n; i += 1) {
    if (client_state[i].status_update_state == STATUS_UPDATE_WAITING) {
      client_state[i].status_update_state = STATUS_UPDATE_PENDING;
      i_rx[i].packet_ready();
    }
  }
}

static unsafe void send_to_clients(client_state_t client_state[n], server ethernet_rx_if i_rx[n],
                                   static const unsigned n, unsigned filter_result,
                                   uint16_t len_type, int &incoming_tcount)
{
  for (int i = 0; i < n; i++) {
    int client_wants_packet = ((filter_result >> i) & 1);
    if (client_state[i].num_etype_filters != 0 && (len_type >= 1536)) {
      int passed_etype_filter = 0;
      for (int j = 0; j < client_state[i].num_etype_filters; j++) {
        if (client_state[i].etype_filters[j] == len_type) {
          passed_etype_filter = 1;
          break;
        }
      }
      client_wants_packet &= passed_etype_filter;
    }
    if (client_wants_packet) {
      client_state[i].incoming_packet = 1;
      i_rx[i].packet_ready();
      incoming_tcount++;
    }
  }
}

static void mii_ethernet_aux(client mii_if i_mii,
                             server ethernet_cfg_if i_cfg[n_cfg],
                             static const unsigned n_cfg,
                             server ethernet_rx_if i_rx[n_rx],
                             static const unsigned n_rx,
                             server ethernet_tx_if i_tx[n_tx],
                             static const unsigned n_tx)
{
  unsafe {
    uint8_t mac_address[MACADDR_NUM_BYTES] = {0};
    ethernet_link_state_t link_status = ETHERNET_LINK_DOWN;
    ethernet_speed_t link_speed = LINK_100_MBPS_FULL_DUPLEX;
    client_state_t client_state[n_rx];
    int txbuf[(ETHERNET_MAX_PACKET_SIZE+3)/4];
    mii_info_t mii_info;
    int incoming_nbytes;
    int incoming_timestamp;
    int incoming_tcount;
    unsigned incoming_appdata;
    int * unsafe incoming_data = null;
    eth_global_filter_info_t filter_info;

    mii_info = i_mii.init();
    init_client_state(client_state, n_rx);

    ethernet_init_filter_table(filter_info);

    while (1) {
      select {
      case i_rx[int i].get_index() -> size_t result:
        result = i;
        break;

      case i_rx[int i].get_packet(ethernet_packet_info_t &desc,
                                   char data[n],
                                   unsigned n):
        if (client_state[i].status_update_state == STATUS_UPDATE_PENDING) {
          data[0] = link_status;
          data[1] = link_speed;
          desc.type = ETH_IF_STATUS;
          desc.src_ifnum = 0;
          desc.timestamp = 0;
          desc.len = 2;
          desc.filter_data = 0;
          client_state[i].status_update_state = STATUS_UPDATE_WAITING;
        } else if (client_state[i].incoming_packet) {
          ethernet_packet_info_t info;
          info.type = ETH_DATA;
          info.timestamp = incoming_timestamp;
          info.src_ifnum = 0;
          info.filter_data = incoming_appdata;
          info.len = incoming_nbytes;
          memcpy(&desc, &info, sizeof(info));
          memcpy(data, incoming_data, incoming_nbytes);
          client_state[i].incoming_packet = 0;
          incoming_tcount--;
        } else {
          desc.type = ETH_NO_DATA;
        }
        if (incoming_data != null && incoming_tcount == 0) {
          i_mii.release_packet(incoming_data);
          incoming_data = null;
        }
        break;

      case i_cfg[int i].get_macaddr(size_t ifnum, uint8_t r_mac_address[MACADDR_NUM_BYTES]):
        memcpy(r_mac_address, mac_address, sizeof mac_address);
        break;

      case i_cfg[int i].set_macaddr(size_t ifnum, uint8_t r_mac_address[MACADDR_NUM_BYTES]):
        memcpy(mac_address, r_mac_address, sizeof r_mac_address);
        break;

      case i_cfg[int i].add_macaddr_filter(size_t client_num, int is_hp,
                                           ethernet_macaddr_filter_t entry) ->
                                             ethernet_macaddr_filter_result_t result:
        if (is_hp)
          fail("Standard MII Ethernet MAC does not support the high priority queue");

        result = ethernet_add_filter_table_entry(filter_info, client_num, is_hp, entry);
        break;

      case i_cfg[int i].del_macaddr_filter(size_t client_num, int is_hp,
                                           ethernet_macaddr_filter_t entry):
        if (is_hp)
          fail("Standard MII Ethernet MAC does not support the high priority queue");

        ethernet_del_filter_table_entry(filter_info, client_num, is_hp, entry);
        break;

      case i_cfg[int i].del_all_macaddr_filters(size_t client_num, int is_hp):
        if (is_hp)
          fail("Standard MII Ethernet MAC does not support the high priority queue");

        ethernet_clear_filter_table(filter_info, client_num, is_hp);
        break;

      case i_cfg[int i].add_ethertype_filter(size_t client_num, uint16_t ethertype):
        client_state_t &client_state = client_state[client_num];
        size_t n = client_state.num_etype_filters;
        assert(n < ETHERNET_MAX_ETHERTYPE_FILTERS);
        client_state.etype_filters[n] = ethertype;
        client_state.num_etype_filters = n + 1;
        break;

      case i_cfg[int i].del_ethertype_filter(size_t client_num, uint16_t ethertype):
        client_state_t &client_state = client_state[client_num];
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
        fail("Outgoing timestamps are not supported in standard MII Ethernet MAC");
        break;
      }

      case i_cfg[int i].set_egress_qav_idle_slope(size_t ifnum, unsigned slope):
        fail("Shaper not supported in standard MII Ethernet MAC");
        break;

      case i_cfg[int i].set_ingress_timestamp_latency(size_t ifnum, ethernet_speed_t speed, unsigned value): {
        fail("Timestamp correction not supported in standard MII Ethernet MAC");
        break;
      }

      case i_cfg[int i].set_egress_timestamp_latency(size_t ifnum, ethernet_speed_t speed, unsigned value): {
        fail("Timestamp correction not supported in standard MII Ethernet MAC");
        break;
      }

      case i_tx[int i]._init_send_packet(unsigned n, unsigned dst_port):
        // Do nothing
        break;

      case i_tx[int i]._get_outgoing_timestamp() -> unsigned timestamp:
        fail("Outgoing timestamps are not supported in standard MII Ethernet MAC");
        break;

      case i_cfg[int i].enable_strip_vlan_tag(size_t client_num):
        fail("VLAN tag stripping not supported in standard MII Ethernet MAC");
        break;

      case i_cfg[int i].disable_strip_vlan_tag(size_t client_num):
        fail("VLAN tag stripping not supported in standard MII Ethernet MAC");
        break;

      case i_cfg[int i].enable_link_status_notification(size_t client_num):
        client_state_t &client_state = client_state[client_num];
        client_state.status_update_state = STATUS_UPDATE_WAITING;
        break;

      case i_cfg[int i].disable_link_status_notification(size_t client_num):
        client_state_t &client_state = client_state[client_num];
        client_state.status_update_state = STATUS_UPDATE_IGNORING;
        break;

      case i_tx[int i]._complete_send_packet(char data[n], unsigned n,
                                             int request_timestamp,
                                             unsigned dst_port):
        memcpy(txbuf, data, n);
        i_mii.send_packet(txbuf, n);
        // wait for the packet to be sent
        mii_packet_sent(mii_info);
        break;

      case i_cfg[int i].set_link_state(int ifnum, ethernet_link_state_t status, ethernet_speed_t speed):
        if (link_status != status) {
          link_status = status;
          link_speed = speed;
          update_client_state(client_state, i_rx, n_rx);
        }
        break;
      case mii_incoming_packet(mii_info):
        int * unsafe data;
        int nbytes;
        unsigned timestamp;
        {data, nbytes, timestamp} = i_mii.get_incoming_packet();

        if (incoming_data) {
          // Can only handle one packet at a time at this level
          i_mii.release_packet(data);
          break;
        }

        if (data) {
          unsigned appdata;
          incoming_timestamp = timestamp;
          incoming_nbytes = nbytes;
          incoming_data = data;
          incoming_tcount = 0;

          int *unsafe p_len_type = (int *unsafe) &data[3];
          uint16_t len_type = (uint16_t) NTOH_U16_ALIGNED(p_len_type);
          unsigned header_len = 14;
          if (len_type == 0x8100) {
            header_len += 4;
            p_len_type = (int *unsafe) &data[4];
            len_type = (uint16_t) NTOH_U16_ALIGNED(p_len_type);
          }
          const unsigned rx_data_len = nbytes - header_len;

          if ((len_type < 1536) && (len_type > rx_data_len)) {
            // Invalid len_type field, will fall out and free the buffer below
          }
          else {
            unsigned filter_result =
              ethernet_do_filtering(filter_info, (char *) data, nbytes,
                                    incoming_appdata);

            if (filter_result) {
              send_to_clients(client_state, i_rx, n_rx,
                              filter_result, len_type, incoming_tcount);
            }
          }
          if (incoming_tcount == 0) {
            i_mii.release_packet(incoming_data);
            incoming_data = null;
          }
        }
        break;
      }
    }
  }
}


void mii_ethernet_mac(server ethernet_cfg_if i_cfg[n_cfg], static const unsigned n_cfg,
                      server ethernet_rx_if i_rx[n_rx], static const unsigned n_rx,
                      server ethernet_tx_if i_tx[n_tx], static const unsigned n_tx,
                      in port p_rxclk, in port p_rxer, in port p_rxd,
                      in port p_rxdv,
                      in port p_txclk, out port p_txen, out port p_txd,
                      port p_timing,
                      clock rxclk,
                      clock txclk,
                      static const unsigned double_rx_bufsize_words)

{
  interface mii_if i_mii;
  par {
      mii(i_mii, p_rxclk, p_rxer, p_rxd, p_rxdv, p_txclk,
          p_txen, p_txd, p_timing,
          rxclk, txclk, double_rx_bufsize_words)
      mii_ethernet_aux(i_mii,
                       i_cfg, n_cfg,
                       i_rx, n_rx,
                       i_tx, n_tx);
  }
}

