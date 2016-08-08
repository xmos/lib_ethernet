// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved

#include "control.h"

void control(port p_ctrl, server control_if ctrl[n], unsigned n, unsigned need_to_exit)
{
  // Enable fast mode to ensure that this core is active
  set_core_fast_mode_on();

  status_t current_status = STATUS_ACTIVE;
  unsigned n_active_processes = need_to_exit;

  while (1) {
    select {
    case current_status != STATUS_DONE => p_ctrl when pinseq(1) :> int tmp:
      current_status = STATUS_DONE;
      for (int i = 0; i < n; i++) {
        ctrl[i].status_changed();
      }
      break;

    case (int i = 0; i < n; i++) ctrl[i].get_status(status_t &status):
      status = current_status;
      break;

    case (int i = 0; i < n; i++) ctrl[i].set_done():
      n_active_processes -= 1;
      if (n_active_processes == 0) {
        _exit(0);
      }
      break;
    }
  }
}
