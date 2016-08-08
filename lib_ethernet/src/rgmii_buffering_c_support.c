// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include "rgmii_buffering.h"

void buffers_free_initialize_c(buffers_free_t *free, unsigned char *buffer)
{
  free->stack[0] = (uintptr_t)buffer;
}

