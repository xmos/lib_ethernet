// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __mii_buffering_defines_h__
#define __mii_buffering_defines_h__

// The number of bytes in the mii_packet_t before the data
#define MII_PACKET_HEADER_BYTES 40
#define MII_PACKET_HEADER_WORDS (MII_PACKET_HEADER_BYTES / 4)

// The amount of space required for the common interrupt handler
#define MII_COMMON_HANDLER_STACK_WORDS 4

// Local max packet size duplicated here to avoid including ethernet.h into assembly
#ifdef __ASSEMBLER__
#define ETHERNET_MAX_PACKET_SIZE (1518)
#endif

#endif //__mii_buffering_defines_h__
