// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include "rgmii_buffering.h"

void buffers_free_initialize_c(buffers_free_t *free, unsigned char *buffer)
{
  free->stack[0] = (uintptr_t)buffer;
}

