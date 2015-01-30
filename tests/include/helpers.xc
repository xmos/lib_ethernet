// Copyright (c) 2015, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

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
