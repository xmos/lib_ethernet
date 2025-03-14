// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef __CONTROL_H__
#define __CONTROL_H__

#ifdef __XC__

typedef enum {
  STATUS_ACTIVE,
  STATUS_DONE
} status_t;

typedef interface control_if {
  [[notification]] slave void status_changed();
  [[clears_notification]] void get_status(status_t &status);
  void set_done();
} control_if;

void control(port p_ctrl, server control_if ctrl[n], unsigned n, unsigned need_to_exit);

#endif // __XC__

#endif // __CONTROL_H__
