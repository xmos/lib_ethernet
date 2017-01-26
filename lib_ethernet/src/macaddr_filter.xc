// Copyright (c) 2014-2017, XMOS Ltd, All rights reserved
#include <string.h>
#include <print.h>
#include "macaddr_filter.h"
#include "xassert.h"

int ethernet_filter_result_is_hp(unsigned value)
{
  return (value >> 31) ? 1 : 0;
}

unsigned ethernet_filter_result_interfaces(unsigned value)
{
  // Throw away bit 31
  return (value << 1) >> 1;
}

unsigned ethernet_filter_result_set_hp(unsigned value, int is_hp)
{
  // Ensure it is a single bit in the LSB
  is_hp = is_hp ? 1 : 0;
  return value | (is_hp << 31);
}

void ethernet_init_filter_table(eth_global_filter_info_t table)
{
  for (size_t i = 0; i < ETHERNET_MACADDR_FILTER_TABLE_SIZE; i++) {
    memset(table[i].addr, 0, sizeof table[i].addr);
    table[i].result = 0;
    table[i].appdata = 0;
  }
}

#pragma unsafe arrays
ethernet_macaddr_filter_result_t
ethernet_add_filter_table_entry(eth_global_filter_info_t table,
                                unsigned client_num, int is_hp,
                                ethernet_macaddr_filter_t entry)
{
  for (size_t i = 0; i < ETHERNET_MACADDR_FILTER_TABLE_SIZE; i++) {
    unsigned *words = (unsigned *)entry.addr;
    unsigned *addr = (unsigned *)table[i].addr;

    int mac_match =
      (table[i].result != 0) &&
      (words[0] == addr[0]) &&
      ((words[1] & 0xffff) == (addr[1] & 0xffff));

    if (!mac_match)
      continue;

    // Ensure that the entry priority matches
    if (ethernet_filter_result_is_hp(table[i].result) != is_hp) {
      // Unsupported to have two clients of different priorities
      // adding filters for the same MAC address
      assert(0);
    }

    // Update the entry.
    table[i].result |= (1 << client_num);
    return ETHERNET_MACADDR_FILTER_SUCCESS;
  }

  // Didn't find the entry in the table already.
  for (size_t i = 0; i < ETHERNET_MACADDR_FILTER_TABLE_SIZE;i++) {
    if (table[i].result != 0)
      continue;

    // Found an empty entry, use it
    memcpy(table[i].addr, entry.addr, sizeof entry.addr);
    table[i].appdata = entry.appdata;
    table[i].result = ethernet_filter_result_set_hp(1 << client_num, is_hp);
    return ETHERNET_MACADDR_FILTER_SUCCESS;
  }

  // Cannot fit the entry in the table.
  return ETHERNET_MACADDR_FILTER_TABLE_FULL;
}

#pragma unsafe arrays
void ethernet_del_filter_table_entry(eth_global_filter_info_t table,
                                     unsigned client_num, int is_hp,
                                     ethernet_macaddr_filter_t entry)
{
  for (size_t i = 0; i < ETHERNET_MACADDR_FILTER_TABLE_SIZE; i++) {
    unsigned *words = (unsigned *)entry.addr;
    unsigned *addr = (unsigned *)table[i].addr;

    int mac_match =
      (table[i].result != 0) &&
      (words[0] == addr[0]) &&
      ((words[1] & 0xffff) == (addr[1] & 0xffff));

    if (!mac_match)
      continue;

    // Ensure the entry is the correct priority
    if (ethernet_filter_result_is_hp(table[i].result) != is_hp)
      continue;

    // Update the entry.
    table[i].result &= ~(1 << client_num);

    // Clear the high priority bit if there are no more clients
    if (is_hp && (ethernet_filter_result_interfaces(table[i].result) == 0)) {
      table[i].result = 0;
    }
  }
}

void ethernet_clear_filter_table(eth_global_filter_info_t table,
                                 unsigned client_num, int is_hp)
{
  for (size_t i = 0; i < ETHERNET_MACADDR_FILTER_TABLE_SIZE; i++) {
    // Update the entry.
    table[i].result &= ~(1 << client_num);

    // Clear the high priority bit if there are no more clients
    if (is_hp && (ethernet_filter_result_interfaces(table[i].result) == 0)) {
      table[i].result = 0;
    }
  }
}

#pragma unsafe arrays
unsigned ethernet_do_filtering(eth_global_filter_info_t table,
                               char buf[packet_size],
                               size_t packet_size,
                               unsigned &appdata)
{
  unsigned result = 0;

  // Do all entries without an early exit so that it is always worst-case timing
  for (size_t i = 0;i < ETHERNET_MACADDR_FILTER_TABLE_SIZE; i++) {
    unsigned *words = (unsigned *)buf;
    unsigned *addr = (unsigned *)table[i].addr;

    int mac_match =
      (table[i].result != 0) &&
      (words[0] == addr[0]) &&
      ((words[1] & 0xffff) == (addr[1] & 0xffff));

    if (!mac_match)
      continue;

    appdata = table[i].appdata;
    result = table[i].result;
  }
  return result;
}
