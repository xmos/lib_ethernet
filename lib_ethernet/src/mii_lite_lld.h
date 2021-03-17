// Copyright 2013-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __mii_lite_lld_h__
#define __mii_lite_lld_h__
#include "hwtimer.h"

extern unsigned int tail_values[4];
extern void mii_lite_lld(buffered in port:32 rxd, in port rxdv,
                         buffered out port:32 txd,
                         chanend INchannel, chanend OUTchannel, in port timing,
                         hwtimer_t tmr);

#endif //__mii_lite_lld_h__
