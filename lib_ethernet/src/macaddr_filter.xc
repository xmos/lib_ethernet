#include <macaddr_filter.h>
#include <string.h>
#include <print.h>
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
    table[i].vlan = 0;
    memset(table[i].addr, 6, 0);
    table[i].result = 0;
    table[i].appdata = 0;
  }
}

ethernet_macaddr_filter_result_t
ethernet_add_filter_table_entry(eth_global_filter_info_t table,
                                unsigned client_id, int is_hp,
                                ethernet_macaddr_filter_t entry)
{
  for (size_t i = 0; i < ETHERNET_MACADDR_FILTER_TABLE_SIZE; i++) {
    // Skip this entry if it is not used
    if (table[i].result == 0)
      continue;

    // Skip this entry if it doesn't match the entry to add.
    if (table[i].vlan != entry.vlan)
      continue;

    int mac_match = 1;
    for (size_t j = 0; j < 6; j++)
      if (table[i].addr[j] != entry.addr[j])
        mac_match = 0;
    if (!mac_match)
      continue;

    // Ensure that the entry priority matches
    if (ethernet_filter_result_is_hp(table[i].result) != is_hp) {
      // Unsupported to have two clients of different priorities
      // adding filters for the same MAC address
      assert(0);
    }

    // Update the entry.
    table[i].result |= (1 << client_id);
    return ETHERNET_MACADDR_FILTER_SUCCESS;
  }

  // Didn't find the entry in the table already.
  for (size_t i = 0; i < ETHERNET_MACADDR_FILTER_TABLE_SIZE;i++) {
    if (table[i].result != 0)
      continue;

    // Found an empty entry, use it
    table[i].vlan = entry.vlan;
    memcpy(table[i].addr, entry.addr, 6);
    table[i].appdata = entry.appdata;
    table[i].result = ethernet_filter_result_set_hp(1 << client_id, is_hp);
    return ETHERNET_MACADDR_FILTER_SUCCESS;
  }

  // Cannot fit the entry in the table.
  return ETHERNET_MACADDR_FILTER_TABLE_FULL;
}

void ethernet_del_filter_table_entry(eth_global_filter_info_t table,
                                     unsigned client_id, int is_hp,
                                     ethernet_macaddr_filter_t entry)
{
  for (size_t i = 0; i < ETHERNET_MACADDR_FILTER_TABLE_SIZE; i++) {
    // Skip this entry if it is not used
    if (table[i].result == 0)
      continue;

    // Skip this entry if it doesn't match the entry to add.
    if (table[i].vlan != entry.vlan)
      continue;
    int mac_match = 1;
    for (size_t j = 0; j < 6; j++)
      if (table[i].addr[j] != entry.addr[j])
        mac_match = 0;
    if (!mac_match)
      continue;

    // Ensure the entry is the correct priority
    if (ethernet_filter_result_is_hp(table[i].result != is_hp))
      continue;

    // Update the entry.
    table[i].result &= ~(1 << client_id);

    // Clear the high priority bit if there are no more clients
    if (is_hp && (ethernet_filter_result_interfaces(table[i].result) == 0)) {
      table[i].result = 0;
    }
  }
}

void ethernet_clear_filter_table(eth_global_filter_info_t table,
                                 unsigned client_id, int is_hp)
{
  for (size_t i = 0; i < ETHERNET_MACADDR_FILTER_TABLE_SIZE; i++) {
    // Update the entry.
    table[i].result &= ~(1 << client_id);

    // Clear the high priority bit if there are no more clients
    if (is_hp && (ethernet_filter_result_interfaces(table[i].result) == 0)) {
      table[i].result = 0;
    }
  }
}

unsigned ethernet_do_filtering(eth_global_filter_info_t table,
                               char buf[packet_size],
                               size_t packet_size,
                               unsigned &appdata)
{
  uint16_t vlan = 0;

  // Check if there is a vlan tag
  if (buf[13] == 0x80 && buf[14] == 0x00)
    vlan = buf[15]&0xf + buf[16];

  for (size_t i = 0;i < ETHERNET_MACADDR_FILTER_TABLE_SIZE; i++) {
    if (table[i].result == 0)
      continue;
    // Skip this entry if it doesn't match the
    if (table[i].vlan != vlan)
      continue;
    int mac_match = 1;
    for (size_t j = 0; j < 6; j++) {
      if (table[i].addr[j] != buf[j])
        mac_match = 0;
    }
    if (!mac_match)
      continue;
    // We have a match.
    appdata = table[i].appdata;
    return table[i].result;
  }
  return 0;
}
