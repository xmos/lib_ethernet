// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#ifndef __mii_lite_lld_h__
#define __mii_lite_lld_h__
#include "hwtimer.h"

extern unsigned int tail_values[4];
extern void mii_lite_lld(buffered in port:32 rxd, in port rxdv,
                         buffered out port:32 txd,
                         chanend INchannel, chanend OUTchannel, in port timing,
                         hwtimer_t tmr);

#endif //__mii_lite_lld_h__
