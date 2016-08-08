// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#ifndef _mii_common_lld_h_
#define _mii_common_lld_h_

#include "mii_buffering_defines.h"

#ifdef __XC__

/** A function to enable the RX_ER port to raise interrupts on errors.
 *
 * This function takes a port which it configures to raise interrupts which will record
 * when an error occurs.
 *
 *   \param p_rxer    The RX_ER port of the ethernet interface.
 *
 *   \returns         A pointer to the memory location in which errors will be recoreded.
 *
 * Notes:
 *  - The user has to ensure that interrupts are enabled for the section of code when
 *     a packet is being received.
 *  - When an error occurs the user also must clear the error flag themselves.
 *  - The error flag will simply be non-zero (do not rely on its actual value).
 *
 */
unsigned * unsafe mii_setup_error_port(in buffered port:1 p_rxer, in port p_rxdv,
                                       unsigned kernel_stack_space[MII_COMMON_HANDLER_STACK_WORDS]);

#endif

#endif // _mii_common_lld_h_
