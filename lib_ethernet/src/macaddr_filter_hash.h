// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#ifndef __macaddr_filter_hash_h__
#define __macaddr_filter_hash_h__

#include "default_ethernet_conf.h"
#include "macaddr_filter.h"

#ifdef __XC__
extern "C" {
#endif

typedef struct mii_macaddr_hash_table_entry_t
{
  unsigned id[2];
  unsigned result;
  unsigned appdata;
} mii_macaddr_hash_table_entry_t;

typedef struct mii_macaddr_hash_table_t
{
  unsigned polys[2];
  unsigned num_entries;
  mii_macaddr_hash_table_entry_t entries[MII_MACADDR_HASH_TABLE_SIZE];
} mii_macaddr_hash_table_t;
  

void mii_macaddr_hash_table_init();
void mii_macaddr_set_num_active_filters(unsigned num_active);

mii_macaddr_hash_table_t *mii_macaddr_get_hash_table(unsigned filter_num);
  
unsigned mii_macaddr_hash_lookup(mii_macaddr_hash_table_t *table,
                                 unsigned key0,
                                 unsigned key1,
                                 unsigned *appdata);

ethernet_macaddr_filter_result_t
mii_macaddr_hash_table_add_entry(unsigned client_num, int is_hp,
                                 ethernet_macaddr_filter_t entry);

void mii_macaddr_hash_table_delete_entry(unsigned client_num, int is_hp,
                                         ethernet_macaddr_filter_t entry);
void mii_macaddr_hash_table_clear();

#ifdef __XC__
}
#endif

#endif // __macaddr_filter_hash_h__
