// Copyright 2013-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <string.h>

#include "ethernet.h"
#include "default_ethernet_conf.h"
#include "rmii_master.h"
#include "mii_filter.h"
#include "mii_buffering.h"
#include "mii_ts_queue.h"
#include "client_state.h"
#define DEBUG_UNIT ETHERNET_CLIENT_HANDLER
#include "debug_print.h"
#include "xassert.h"
#include "print.h"
#include "server_state.h"
#include "rmii_rx_pins_exit.h"

// These helpers allow the port to be reconfigured and work-around not being able to cast a port type in XC
static in buffered port:32 * unsafe enable_buffered_in_port(unsigned *port_pointer, unsigned transferWidth)
{
    asm volatile("setc res[%0], %1"::"r"(*port_pointer), "r"(XS1_SETC_INUSE_ON));
    asm volatile("setc res[%0], %1"::"r"(*port_pointer), "r"(XS1_SETC_BUF_BUFFERS));
    asm volatile("settw res[%0], %1"::"r"(*port_pointer),"r"(transferWidth));
    in buffered port:32 * unsafe bpp = NULL;
    asm("add %0, %1, %2": "=r"(bpp) : "r"(port_pointer), "r"(0)); // Copy
    return bpp;
}

static out buffered port:32 * unsafe enable_buffered_out_port(unsigned *port_pointer, unsigned transferWidth)
{
    asm volatile("setc res[%0], %1"::"r"(*port_pointer), "r"(XS1_SETC_INUSE_ON));
    asm volatile("setc res[%0], %1"::"r"(*port_pointer), "r"(XS1_SETC_BUF_BUFFERS));
    asm volatile("setclk res[%0], %1"::"r"(*port_pointer), "r"(XS1_CLKBLK_REF)); // Set to ref clk initially. We override this later
    asm volatile("settw res[%0], %1"::"r"(*port_pointer),"r"(transferWidth));
    out buffered port:32 * unsafe bpp = NULL;
    asm("add %0, %1, %2": "=r"(bpp) : "r"(port_pointer), "r"(0)); // Copy
    return bpp;
}


void rmii_ethernet_rt_mac(SERVER_INTERFACE(ethernet_cfg_if, i_cfg[n_cfg]), static_const_unsigned_t n_cfg,
                          SERVER_INTERFACE(ethernet_rx_if, i_rx_lp[n_rx_lp]), static_const_unsigned_t n_rx_lp,
                          SERVER_INTERFACE(ethernet_tx_if, i_tx_lp[n_tx_lp]), static_const_unsigned_t n_tx_lp,
                          nullable_streaming_chanend_t c_rx_hp,
                          nullable_streaming_chanend_t c_tx_hp,
                          in_port_t p_clk,
                          port p_rxd_0, NULLABLE_RESOURCE(port, p_rxd_1), rmii_data_4b_pin_assignment_t rx_pin_map,
                          in_port_t p_rxdv,
                          out_port_t p_txen,
                          port p_txd_0, NULLABLE_RESOURCE(port, p_txd_1), rmii_data_4b_pin_assignment_t tx_pin_map,
                          clock rxclk,
                          clock txclk,
                          static_const_unsigned_t rx_bufsize_words,
                          static_const_unsigned_t tx_bufsize_words,
                          enum ethernet_enable_shaper_t shaper_enabled)
{
  // Establish types of data ports presented
  unsafe{
    // Setup buffering
    unsigned int rx_data[rx_bufsize_words];
    unsigned int tx_data[tx_bufsize_words];
    mii_mempool_t rx_mem = mii_init_mempool(rx_data, rx_bufsize_words*4);

    // If the high priority traffic is connected then allocate half the buffer for high priority
    // and half for low priority. Otherwise, allocate it all to low priority.
    const size_t lp_buffer_bytes = !isnull(c_tx_hp) ? tx_bufsize_words * 2 : tx_bufsize_words * 4;
    const size_t hp_buffer_bytes = tx_bufsize_words * 4 - lp_buffer_bytes;
    mii_mempool_t tx_mem_lp = mii_init_mempool(tx_data, lp_buffer_bytes);
    mii_mempool_t tx_mem_hp = mii_init_mempool(tx_data + (lp_buffer_bytes/4), hp_buffer_bytes);

    packet_queue_info_t rx_packets_lp, rx_packets_hp, tx_packets_lp, tx_packets_hp, incoming_packets;
    mii_init_packet_queue((mii_packet_queue_t)&rx_packets_lp);
    mii_init_packet_queue((mii_packet_queue_t)&rx_packets_hp);
    mii_init_packet_queue((mii_packet_queue_t)&tx_packets_lp);
    mii_init_packet_queue((mii_packet_queue_t)&tx_packets_hp);
    mii_init_packet_queue((mii_packet_queue_t)&incoming_packets);

    // Shared read pointer to help optimize the RX code
    unsigned rx_rdptr = 0;
    unsigned * unsafe p_rx_rdptr = &rx_rdptr;


    mii_init_lock();

    mii_ts_queue_entry_t ts_fifo[MII_TIMESTAMP_QUEUE_MAX_SIZE + 1];
    mii_ts_queue_info_t ts_queue_info;

    if (n_tx_lp > MII_TIMESTAMP_QUEUE_MAX_SIZE) {
      fail("Exceeded maximum number of transmit clients. Increase MII_TIMESTAMP_QUEUE_MAX_SIZE in ethernet_conf.h");
    }

    if (!ETHERNET_SUPPORT_HP_QUEUES && (!isnull(c_rx_hp) || !isnull(c_tx_hp))) {
      fail("Using high priority channels without #define ETHERNET_SUPPORT_HP_QUEUES set true");
    }

    mii_ts_queue_t ts_queue = mii_ts_queue_init(&ts_queue_info, ts_fifo, n_tx_lp + 1);



    // Common initialisation
    set_port_use_on(p_clk); // RMII 50MHz clock input port

    // Setup RX data ports
    // First declare C pointers for port resources
    in buffered port:32 * unsafe rx_data_0 = NULL;
    in buffered port:32 * unsafe rx_data_1 = NULL;

    // Extract width and optionally which 4b pins to use
    unsigned rx_port_width = ((unsigned)(p_rxd_0) >> 16) & 0xff;

    // Extract pointers to ports with correct port qualifiers and setup data pins
    switch(rx_port_width){
      case 4:
        rx_data_0 = enable_buffered_in_port((unsigned*)(&p_rxd_0), 32);
        rmii_master_init_rx_4b(p_clk, rx_data_0, p_rxdv, rxclk);
        break;
      case 1:
        rx_data_0 = enable_buffered_in_port((unsigned*)&p_rxd_0, 32);
        rx_data_1 = enable_buffered_in_port((unsigned*)&p_rxd_1, 32);
        rmii_master_init_rx_1b(p_clk, rx_data_0, rx_data_1, p_rxdv, rxclk);
        break;
      default:
        fail("Invald port width for RMII Rx");
        break;
    }

    // Setup TX data ports
    out buffered port:32 * unsafe tx_data_0 = NULL;
    out buffered port:32 * unsafe tx_data_1 = NULL;

    unsigned tx_port_width = ((unsigned)(p_txd_0) >> 16) & 0xff;

    switch(tx_port_width){
      case 4:
        tx_data_0 = enable_buffered_out_port((unsigned*)(&p_txd_0), 32);
        rmii_master_init_tx_4b(p_clk, tx_data_0, p_txen, txclk);
        break;
      case 1:
        tx_data_0 = enable_buffered_out_port((unsigned*)&p_txd_0, 32);
        tx_data_1 = enable_buffered_out_port((unsigned*)&p_txd_1, 32);
        rmii_master_init_tx_1b(p_clk, tx_data_0, tx_data_1, p_txen, txclk);
        break;
      default:
        fail("Invald port width for RMII Tx");
        break;
    }

    // Setup server
    ethernet_port_state_t port_state;
    init_server_port_state(port_state, shaper_enabled == ETHERNET_ENABLE_SHAPER);

    ethernet_port_state_t * unsafe p_port_state = (ethernet_port_state_t * unsafe)&port_state;

    // Exit flag and chanend
    int rmii_ethernet_rt_mac_running = 1;
    int * unsafe running_flag_ptr = &rmii_ethernet_rt_mac_running;
    chan c_rx_pins_exit;

    chan c_conf;
    par {
      // Rx task
      {
        if(rx_port_width == 4){
          rmii_master_rx_pins_4b(rx_mem,
                                 (mii_packet_queue_t)&incoming_packets,
                                 p_rx_rdptr,
                                 p_rxdv,
                                 rx_data_0,
                                 rx_pin_map,
                                 running_flag_ptr,
                                 c_rx_pins_exit);
        } else {
          rmii_master_rx_pins_1b(rx_mem,
                                 (mii_packet_queue_t)&incoming_packets,
                                 p_rx_rdptr,
                                 p_rxdv,
                                 rx_data_0,
                                 rx_data_1,
                                 running_flag_ptr,
                                 c_rx_pins_exit);
        }
      }
      // Tx task

      rmii_master_tx_pins(tx_mem_lp,
                          tx_mem_hp,
                          (mii_packet_queue_t)&tx_packets_lp,
                          (mii_packet_queue_t)&tx_packets_hp,
                          ts_queue,
                          tx_port_width,
                          tx_data_0,
                          tx_data_1,
                          tx_pin_map,
                          txclk,
                          p_port_state,
                          running_flag_ptr);

      mii_ethernet_filter(c_conf,
                          (mii_packet_queue_t)&incoming_packets,
                          (mii_packet_queue_t)&rx_packets_lp,
                          (mii_packet_queue_t)&rx_packets_hp,
                          running_flag_ptr);

      mii_ethernet_server(rx_mem,
                          (mii_packet_queue_t)&rx_packets_lp,
                          (mii_packet_queue_t)&rx_packets_hp,
                          p_rx_rdptr,
                          tx_mem_lp,
                          tx_mem_hp,
                          (mii_packet_queue_t)&tx_packets_lp,
                          (mii_packet_queue_t)&tx_packets_hp,
                          ts_queue,
                          i_cfg, n_cfg,
                          i_rx_lp, n_rx_lp,
                          i_tx_lp, n_tx_lp,
                          c_rx_hp,
                          c_tx_hp,
                          c_conf,
                          p_port_state,
                          running_flag_ptr,
                          c_rx_pins_exit,
                          ETH_MAC_IF_RMII);
    } // par

    // If exit occurred, disable used ports and resources so they are left in a good state
    mii_deinit_lock();

    stop_clock(rxclk);
    switch(rx_port_width){
      case 4:
        set_port_use_off(*rx_data_0);
        break;
      case 1:
        set_port_use_off(*rx_data_0);
        set_port_use_off(*rx_data_1);
        break;
      default:
        fail("Invald port width for RMII Rx");
        break;
    }
    set_port_use_off(p_rxdv);

    stop_clock(txclk);
    switch(tx_port_width){
      case 4:
        set_port_use_off(*tx_data_0);
        break;
      case 1:
        set_port_use_off(*tx_data_0);
        set_port_use_off(*tx_data_1);
        break;
      default:
        fail("Invald port width for RMII Tx");
        break;
    }
    set_port_use_off(p_txen);

    set_clock_off(rxclk);
    set_clock_off(txclk);
    set_port_use_off(p_clk);

    // All MII memory is reserved from the stack of this function so will be cleaned automatically

  } // unsafe block
}
