// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include <mii.h>
#include <xs1.h>
#include "mii_master.h"
#include "mii_lite_driver.h"

void mii_driver(in port p_rxclk, in port p_rxer0, in port p_rxd0,
                in port p_rxdv,
                in port p_txclk, out port p_txen, out port p_txd0,
                port p_timing,
                clock rxclk,
                clock txclk,
                chanend c_in, chanend c_out, chanend c_notif)
{
  in port * movable pp_rxd0 = &p_rxd0;
  in buffered port:32 * movable pp_rxd = reconfigure_port(move(pp_rxd0), in buffered port:32);
  in buffered port:32 &p_rxd = *pp_rxd;
  out port * movable pp_txd0 = &p_txd0;
  out buffered port:32 * movable pp_txd = reconfigure_port(move(pp_txd0), out buffered port:32);
  out buffered port:32 &p_txd = *pp_txd;
  in port * movable pp_rxer0 = &p_rxer0;
  in buffered port:1 * movable pp_rxer = reconfigure_port(move(pp_rxer0), in buffered port:1);
  in buffered port:1 &p_rxer = *pp_rxer;
  mii_master_init(p_rxclk, p_rxd, p_rxdv, rxclk, p_txclk, p_txen, p_txd, txclk, p_rxer);
  mii_lite_driver(p_rxd, p_rxdv, p_txd, p_timing, c_in, c_out);
}

[[distributable]]
void mii_handler(chanend c_in, chanend c_out,
                 chanend notifications,
                 server mii_if i_mii,
                 static const unsigned double_rx_bufsize_words)
{
  int rxbuf[double_rx_bufsize_words];
  struct mii_lite_data_t mii_lite_data;

  while (1) {
    select {
    case i_mii.init(void) -> mii_info_t info:
      unsafe {
        info = (mii_info_t) &mii_lite_data;
      }
        // Setup buffering and interrupt for packet handling
      mii_lite_buffer_init(mii_lite_data, c_in, notifications, c_out,
                           rxbuf, double_rx_bufsize_words);
      mii_lite_out_init(c_out);
      break;
    case i_mii.release_packet(int * unsafe data):
      mii_lite_free_in_buffer(mii_lite_data, (char * unsafe) data);
      break;
    case i_mii.get_incoming_packet() -> {int * unsafe data,
                                         size_t nbytes,
                                         unsigned timestamp}:
      {data, nbytes, timestamp} = mii_lite_get_in_buffer(mii_lite_data, notifications);
      break;
    case i_mii.send_packet(int * unsafe txbuf, size_t n):
      unsafe {
        mii_lite_out_packet(c_out, txbuf, 0, n);
      }
      break;
    }
  }
}

