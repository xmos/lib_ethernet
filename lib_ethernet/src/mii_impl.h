// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#ifndef __mii_impl_h__
#define __mii_impl_h__
#include <xs1.h>
#include "mii.h"
#include <mii_lite_driver.h>
#ifdef __XC__

[[distributable]]
void mii_handler(chanend c_in, chanend c_out,
                 chanend notifications,
                 server mii_if i_mii,
                 static const unsigned double_rx_bufsize_words);


void mii_driver(in port p_rxclk, in port p_rxer, in port p_rxd0,
                in port p_rxdv,
                in port p_txclk, out port p_txen, out port p_txd0,
                port p_timing,
                clock rxclk,
                clock txclk,
                chanend c_in, chanend c_out, chanend c_notif);

typedef unsafe chanend mii_unsafe_chanend;

inline mii_unsafe_chanend mii_get_notification_chanend(mii_lite_data_t * unsafe p)
{
  unsafe {
    return p->notification_channel_end;
  }
}

#define mii_incoming_packet(x) mii_incoming_packet_(mii_get_notification_chanend(x), x)

#pragma select handler
inline void mii_incoming_packet_(unsafe chanend c, mii_lite_data_t * unsafe p) {
  unsafe {
    p->notify_seen = inuchar((chanend) c);
  }
}

inline mii_unsafe_chanend mii_get_out_chanend(mii_lite_data_t * unsafe p)
{
  unsafe {
    return p->mii_out_channel;
  }
}

#define mii_packet_sent(x) mii_packet_sent_(mii_get_out_chanend(x))

#pragma select handler
inline void mii_packet_sent_(unsafe chanend c) {
  unsafe {
    chkct((chanend) c, XS1_CT_END);
  }
}

#define mii(i_mii, p_rxclk, p_rxer, p_rxd, p_rxdv, p_txclk, p_txen, p_txd, p_timing, rxclk, txclk, double_rx_bufsize_words) \
  { chan c_in, c_out, c_notif;\
    par {\
      mii_driver(p_rxclk, p_rxer, p_rxd, p_rxdv, p_txclk,   \
                 p_txen, p_txd, p_timing, rxclk, txclk,     \
                 c_in, c_out, c_notif);                     \
      mii_handler(c_in, c_out, c_notif, i_mii, \
                               double_rx_bufsize_words);    \
    } \
  }

#endif

#endif // __mii_impl_h__
