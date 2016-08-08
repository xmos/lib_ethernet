// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <print.h>
#include "hwlock.h"
#include "string.h"
#include "macaddr_filter_hash.h"

static mii_macaddr_hash_table_t hash_table_0;
static mii_macaddr_hash_table_t hash_table_1;

static mii_macaddr_hash_table_t *hash_table = &hash_table_0;
static mii_macaddr_hash_table_t *backup_table = &hash_table_1;

static unsigned int a = 1664525;
static unsigned int c = 1013904223;

// There can be one or two filter threads active
#define MAX_NUM_FILTERS 2
static unsigned filter_active[MAX_NUM_FILTERS];
static unsigned waiting_for_filter[MAX_NUM_FILTERS];

static void clear_table(mii_macaddr_hash_table_t * table)
{
  table->num_entries = 0;
  for (unsigned i = 0; i < MII_MACADDR_HASH_TABLE_SIZE; i++) {
    table->entries[i].id[0] = 0;
    table->entries[i].id[1] = 0;
  }
  table->polys[0] = 0xedb88320;
  table->polys[1] = 0xba75fe21;
}

void mii_macaddr_hash_table_init()
{
  clear_table(hash_table);
  clear_table(backup_table);
}

void mii_macaddr_set_num_active_filters(unsigned num_active)
{
  for (int i = 0; i < MAX_NUM_FILTERS; i++) {
    filter_active[i] = 0;
    waiting_for_filter[i] = 0;
  }
  
  for (int i = 0; i < num_active; i++) {
    filter_active[i] = 1;
  }
}

static inline void entry_to_keys(ethernet_macaddr_filter_t entry,
                                 unsigned *key0, unsigned *key1)
{
  *key0 = entry.addr[0] <<  0 |
          entry.addr[1] <<  8 |
          entry.addr[2] << 16 |
          entry.addr[3] << 24;
  *key1 = entry.addr[4] <<  0 |
          entry.addr[5] <<  8;
}

static inline int hash(int key0, int key1, int poly)
{
  unsigned int x = key0;

  __asm("crc32 %0, %2, %3":"=r"(x):"0"(x),"r"(key1),"r"(poly));
  __asm("crc32 %0, %2, %3":"=r"(x):"0"(x),"r"(0),"r"(poly));

  x = x & (MII_MACADDR_HASH_TABLE_SIZE-1);
  return x;
}

mii_macaddr_hash_table_t *mii_macaddr_get_hash_table(unsigned filter_num)
{
  mii_macaddr_hash_table_t *table = hash_table;

  // Clear the waiting bit to indicate that the table has been swapped
  volatile unsigned *p_waiting_for_filter = (volatile unsigned *)(&waiting_for_filter[filter_num]);
  *p_waiting_for_filter = 0;
  
  return table;
} 
  
unsigned mii_macaddr_hash_lookup(mii_macaddr_hash_table_t *table,
                                 unsigned key0,
                                 unsigned key1,
                                 unsigned *appdata)
{
  if (key0 == 0 && key1 == 0)
    return 0;

  // Always perform both lookups to ensure lookup time remains
  // relatively constant
  unsigned int x = hash(key0, key1, table->polys[0]);
  unsigned int y = hash(key0, key1, table->polys[1]);
  
  if (key0 == table->entries[y].id[0] &&
      key1 == table->entries[y].id[1]) {
    *appdata = table->entries[y].appdata;
    return table->entries[y].result;
  }
  
  if (key0 == table->entries[x].id[0] &&
      key1 == table->entries[x].id[1]) {
    *appdata = table->entries[x].appdata;
    return table->entries[x].result;
  }

  return 0;
}


static int contains_different_entry(unsigned index, unsigned key[2], int *empty)
{
  *empty =
    backup_table->entries[index].id[0] == 0
    &&
    backup_table->entries[index].id[1] == 0;

  int different =
    backup_table->entries[index].id[0] != key[0]
    ||
    backup_table->entries[index].id[1] != key[1];

  return (!*empty && different);
}

static int insert(unsigned key0, unsigned key1,
                  unsigned result, unsigned set_not_or,
                  unsigned appdata)
{
  int count = 0;
  int conflict = 0;
  int hashtype = 0;

  mii_macaddr_hash_table_entry_t current;
  current.id[0] = key0;
  current.id[1] = key1;
  current.result = result;
  current.appdata = appdata;
  do {
    int index = hash(current.id[0], current.id[1], backup_table->polys[hashtype]);

    int empty = 0;
    if (!contains_different_entry(index, current.id, &empty)) {
      backup_table->entries[index].id[0] = current.id[0];
      backup_table->entries[index].id[1] = current.id[1];

      // Should only OR the value into an existing entry
      if (set_not_or || empty)
        backup_table->entries[index].result = current.result;
      else
        backup_table->entries[index].result |= current.result;
      
      backup_table->entries[index].appdata = current.appdata;
      conflict = 0;
    }
    else {
      conflict = 1;
      if (count == 0) {
        hashtype = 1 - hashtype;
      }
      else {
        mii_macaddr_hash_table_entry_t tmp;
        memcpy(&tmp, &backup_table->entries[index], sizeof(tmp));

        backup_table->entries[index].id[0] = current.id[0];
        backup_table->entries[index].id[1] = current.id[1];
        backup_table->entries[index].result = current.result;
        backup_table->entries[index].appdata = current.appdata;

        // There is no need to OR in the result any more
        set_not_or = 1;

        memcpy(&current, &tmp, sizeof(tmp));
        hashtype = 1 - hashtype;
      }
    }

    count++;
  } while (conflict && count < (backup_table->num_entries + 10));

  if (!conflict)
    backup_table->num_entries++;

  return !conflict;
}

static void refill_backup_table() {
  // clear the backup table
  backup_table->num_entries = 0;
  for (int i = 0; i < MII_MACADDR_HASH_TABLE_SIZE; i++) {
    backup_table->entries[i].id[0] = 0;
    backup_table->entries[i].id[1] = 0;
  }

  int success;
  do {
    // change the poly
    backup_table->polys[0] = a * backup_table->polys[0] + c;
    backup_table->polys[1] = a * backup_table->polys[1] + c;
    success = 1;
    for (int i = 0; success && i < MII_MACADDR_HASH_TABLE_SIZE; i++) {
      if (hash_table->entries[i].id[0] != 0 ||
          hash_table->entries[i].id[1] != 0) {
        success = insert(hash_table->entries[i].id[0],
                         hash_table->entries[i].id[1],
                         hash_table->entries[i].result, 1, 
                         hash_table->entries[i].appdata);
      }
    }
  } while (!success);
}

static void swap_tables(int do_memcpy)
{
  mii_macaddr_hash_table_t *old_table = hash_table;
  
  // flip the tables
  hash_table = backup_table;
    
  // Wait for filter clients to start using the updated table
  for (int i = 0; i < MAX_NUM_FILTERS; i++) {
    if (filter_active[i]) {
      // Ensure that the accesses to this value go to memory
      volatile unsigned *p_waiting_for_filter = (volatile unsigned *)(&waiting_for_filter[i]);
      *p_waiting_for_filter = 1;
    }
  }

  backup_table = old_table;

  for (int i = 0; i < MAX_NUM_FILTERS; i++) {
    int retries = 100;
    
    // Ensure that the accesses to this value go to memory
    volatile unsigned *p_waiting_for_filter = (volatile unsigned *)(&waiting_for_filter[i]);
    while (*p_waiting_for_filter && retries) {
      // Wait for the table to be taken by the filter threads - with a get-out clause for
      // the case the speed change has happenend
      retries -= 1;
    }
    
    if (!retries) {
      break;
    }
  }

  if (do_memcpy) {
    // Keep tables in sync by doing a copy. If not, the calling function
    // needs to apply their operation again to the new backup table.
    memcpy(backup_table, hash_table, sizeof(hash_table_0));
  }
}

ethernet_macaddr_filter_result_t
mii_macaddr_hash_table_add_entry(unsigned client_num, int is_hp,
                                 ethernet_macaddr_filter_t entry)
{
  unsigned key0, key1;
  entry_to_keys(entry, &key0, &key1);

  int success = 0;
  int do_memcpy = 0;
  while (!success) {
    success = insert(key0, key1,
                     ethernet_filter_result_set_hp(1 << client_num, is_hp), 0,
                     entry.appdata);

    if (success) {
      swap_tables(do_memcpy);
    }
    else {
      // refill table with a different hash and try again
      refill_backup_table();

      // Get the update to do a memcpy of the table to keep the table in sync
      do_memcpy = 1;
    }
  }

  if (!do_memcpy) {
    // The tables need to be kept in sync by performing the same operation
    // as it is quicker than doing a full memcpy
    insert(key0, key1,
           ethernet_filter_result_set_hp(1 << client_num, is_hp), 0,
           entry.appdata);
  }
  
  return ETHERNET_MACADDR_FILTER_SUCCESS;
}

static int delete_entry(unsigned client_num, int is_hp,
                        ethernet_macaddr_filter_t entry)
{
  unsigned key0, key1;
  entry_to_keys(entry, &key0, &key1);

  if (key0 == 0 && key1 == 0)
    return 0;

  unsigned int x = hash(key0, key1, backup_table->polys[0]);

  if (key0 != backup_table->entries[x].id[0] ||
      key1 != backup_table->entries[x].id[1]) { 
    x = hash(key0, key1, hash_table->polys[1]);
  }

  if (key0 != backup_table->entries[x].id[0] ||
      key1 != backup_table->entries[x].id[1]) {
    return 0;
  }
  
  // Update the entry.
  unsigned result = backup_table->entries[x].result;

  // Ensure the entry is the correct priority
  if (ethernet_filter_result_is_hp(result) != is_hp)
    return 0;

  // Clear the client
  result &= ~(1 << client_num);

  // Clear the high priority bit if there are no more clients
  if (is_hp && (ethernet_filter_result_interfaces(result) == 0)) {
    result = 0;
  }
  backup_table->entries[x].result = result;

  return 1;
}
  

void mii_macaddr_hash_table_delete_entry(unsigned client_num, int is_hp,
                                         ethernet_macaddr_filter_t entry)
{
  int deleted = delete_entry(client_num, is_hp, entry);
  if (deleted) {
    swap_tables(0);

    // Re-apply the deletion to keep the tables in sync
    delete_entry(client_num, is_hp, entry);
  }
}

void mii_macaddr_hash_table_clear()
{
  clear_table(backup_table);
  swap_tables(0);

  // Apply clear operation to new backup table (quicker than copying a blank table)
  clear_table(backup_table);
}
