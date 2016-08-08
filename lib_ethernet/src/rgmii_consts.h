// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include <xs1.h>

#define RGMII_DELAY 1
#define RGMII_DIVIDE_1G 3
#define RGMII_DELAY_100M 3
#define RGMII_DIVIDE_100M (((RGMII_DIVIDE_1G + 1) * 5) - 1)

#ifndef INITIAL_MODE
  #define INITIAL_MODE INBAND_STATUS_OFF
#endif

// The inter-frame gap is 96 bit times (1 clock tick at 100Mb/s). However,
// the EOF time stamp is taken when the last but one word goes into the
// transfer register, so that leaves 96 bits of data still to be sent
// on the wire (shift register word, transfer register word, crc word).
// In the case of a non word-aligned transfer compensation is made for
// that in the code at runtime.
// The adjustment is due to the fact that the instruction
// that reads the timer is the next instruction after the out at the
// end of the packet and the timer wait is an instruction before the
// out of the pre-amble
#if INITIAL_MODE == INBAND_STATUS_1G_FULLDUPLEX
#define RGMII_DIVIDE RGMII_DIVIDE_1G
#else
#define RGMII_DIVIDE RGMII_DIVIDE_100M
#endif

#define RGMII_ETHERNET_IFS_AS_REF_CLOCK_COUNT  ((96 + 96 - 10) * (RGMII_DIVIDE + 1)/2)