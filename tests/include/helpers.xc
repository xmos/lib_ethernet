// Copyright (c) 2015-2017, XMOS Ltd, All rights reserved

#include "helpers.h"
#include "random.xc"
#include "random_init.c"

#ifndef RANDOM_FAST_MODE
#define RANDOM_FAST_MODE (1)
#endif

void filler(int seed)
{
  random_generator_t rand = random_create_generator_from_seed(seed);
  timer tmr;
  unsigned time;

  tmr :> time;

  if (RANDOM_FAST_MODE) {
    while (1) {
      // Keep this core busy (randomly going in/out of fast mode)
      set_core_fast_mode_on();
      time += random_get_random_number(rand) % 500;
      tmr when timerafter(time) :> int _;

      set_core_fast_mode_off();
      time += random_get_random_number(rand) % 100;
      tmr when timerafter(time) :> int _;
    }
  } else {
    set_core_fast_mode_on();
    while(1) {
      // Keep this core busy
    }
  }
}

#if RGMII
#define ETHERNET_MACADDR_FILTER_TABLE_SIZE 256
#else
#define ETHERNET_MACADDR_FILTER_TABLE_SIZE 30
#endif

int active_table_entries[ETHERNET_MACADDR_FILTER_TABLE_SIZE];

void mac_addr_filler(client ethernet_cfg_if i_cfg, int seed, int active_count,
                     unsigned interface_num, int is_hp, int rate)
{
  // A core to randomly add/remove MAC addresses. It keeps track of what it has
  // added so that it can safely remove them
  set_core_fast_mode_on();

  random_generator_t rand = random_create_generator_from_seed(seed);
  timer tmr;
  unsigned time;

  ethernet_macaddr_filter_t macaddr_filter;
  macaddr_filter.appdata = 0;
  for (int i = 0; i < MACADDR_NUM_BYTES; i++)
    macaddr_filter.addr[i] = 0x20 | i;

  while (1) {
    tmr :> time;
    time += random_get_random_number(rand) % rate;
    tmr when timerafter(time) :> int _;

    if ((random_get_random_number(rand) & 0xff) < 200) {
      // Add an entry
      while (1) {
        int index = random_get_random_number(rand) % ETHERNET_MACADDR_FILTER_TABLE_SIZE;
        if (active_table_entries[index])
          continue;

        active_table_entries[index] = index + 1;
        macaddr_filter.addr[5] = index + 1;
        i_cfg.add_macaddr_filter(interface_num, is_hp, macaddr_filter);
        break;
      }
    }
    else {
      // Remove an entry
      for (int i = 0; i < ETHERNET_MACADDR_FILTER_TABLE_SIZE; i++) {
        if (!active_table_entries[i])
          continue;

        int index = active_table_entries[i];
        macaddr_filter.addr[5] = index + 1;
        i_cfg.del_macaddr_filter(interface_num, is_hp, macaddr_filter);
        active_table_entries[i] = 0;
      }
    }
  }
}
