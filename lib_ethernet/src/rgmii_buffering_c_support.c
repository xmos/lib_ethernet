#include "rgmii_buffering.h"

void buffers_free_initialise_c(buffers_free_t *free, unsigned char *buffer)
{
  free->stack[0] = (uintptr_t)buffer;
}

