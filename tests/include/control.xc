// Copyright (c) 2015, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include "control.h"

void control(port p_ctrl, server control_if ctrl)
{
  int tmp;
  status_t current_status = STATUS_ACTIVE;

  while (1) {
    select {
    case current_status != STATUS_DONE => p_ctrl when pinseq(1) :> tmp:
      current_status = STATUS_DONE;
      ctrl.status_changed();
      break;
    case ctrl.get_status(status_t &status):
      status = current_status;
      break;
    }
  }
}
