// Copyright (c) 2014-2017, XMOS Ltd, All rights reserved
#ifndef __macaddr_filter_h__
#define __macaddr_filter_h__
#include "ethernet.h"
#include "default_ethernet_conf.h"

// This is the worst-case that can be supported for line-rate processing
#define ETHERNET_MACADDR_FILTER_TABLE_SIZE 30

typedef struct eth_global_filter_entry_t {
  char addr[MACADDR_NUM_BYTES];
  unsigned result;
  unsigned appdata;
} eth_global_filter_entry_t;

typedef eth_global_filter_entry_t eth_global_filter_info_t[ETHERNET_MACADDR_FILTER_TABLE_SIZE];

int ethernet_filter_result_is_hp(unsigned value);
unsigned ethernet_filter_result_interfaces(unsigned value);
unsigned ethernet_filter_result_set_hp(unsigned value, int is_hp);

void ethernet_init_filter_table(eth_global_filter_info_t table);

ethernet_macaddr_filter_result_t
ethernet_add_filter_table_entry(eth_global_filter_info_t table,
                                unsigned client_num, int is_hp,
                                ethernet_macaddr_filter_t entry);

void ethernet_del_filter_table_entry(eth_global_filter_info_t table,
                                     unsigned client_num, int is_hp,
                                     ethernet_macaddr_filter_t entry);

void ethernet_clear_filter_table(eth_global_filter_info_t table,
                                 unsigned client_num, int is_hp);

#ifdef __XC__

unsigned ethernet_do_filtering(eth_global_filter_info_t table,
                               char buf[packet_size],
                               size_t packet_size,
                               unsigned &appdata);

#endif

#endif // __macaddr_filter_h__
