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



{unsigned, rmii_data_4b_pin_assignment_t, in buffered port:32 * unsafe,in buffered port:32 * unsafe}
    init_rx_ports(in_port_t p_clk,
                  in_port_t p_rxdv,
                  clock rxclk,
                  rmii_data_port_t * unsafe p_rxd){
    unsafe {
        in buffered port:32 * unsafe rx_data_0 = NULL;
        in buffered port:32 * unsafe rx_data_1 = NULL;
        // Extract width and optionally which 4b pins to use
        unsigned rx_port_width = ((unsigned)(p_rxd->rmii_data_1b.data_0) >> 16) & 0xff;
        rmii_data_4b_pin_assignment_t rx_port_4b_pins = (rmii_data_4b_pin_assignment_t)(p_rxd->rmii_data_1b.data_1);

        // Extract pointers to ports with correct port qualifiers and setup data pins
        switch(rx_port_width){
          case 4:
            rx_data_0 = enable_buffered_in_port((unsigned*)(&p_rxd->rmii_data_1b.data_0), 32);
            rmii_master_init_rx_4b(p_clk, rx_data_0, p_rxdv, rxclk);
            break;
          case 1:
            rx_data_0 = enable_buffered_in_port((unsigned*)&p_rxd->rmii_data_1b.data_0, 32);
            rx_data_1 = enable_buffered_in_port((unsigned*)&p_rxd->rmii_data_1b.data_1, 32);
            rmii_master_init_rx_1b(p_clk, rx_data_0, rx_data_1, p_rxdv, rxclk);
            break;
          default:
            fail("Invald port width for RMII Rx");
            break;
        }

        return {rx_port_width, rx_port_4b_pins, rx_data_0, rx_data_1};
    }
}


{unsigned, rmii_data_4b_pin_assignment_t, out buffered port:32 * unsafe, out buffered port:32 * unsafe}
    init_tx_ports(in_port_t p_clk,
                  out_port_t p_txen,
                  clock txclk,
                  rmii_data_port_t * unsafe p_txd){
    unsafe {
        out buffered port:32 * unsafe tx_data_0;
        out buffered port:32 * unsafe tx_data_1;
        unsigned tx_port_width = ((unsigned)(p_txd->rmii_data_1b.data_0) >> 16) & 0xff;
        rmii_data_4b_pin_assignment_t tx_port_4b_pins = (rmii_data_4b_pin_assignment_t)(p_txd->rmii_data_1b.data_1);

        switch(tx_port_width){
        case 4:
            tx_data_0 = enable_buffered_out_port((unsigned*)(&p_txd->rmii_data_1b.data_0), 32);
            rmii_master_init_tx_4b(p_clk, tx_data_0, p_txen, txclk);
            break;
        case 1:
            tx_data_0 = enable_buffered_out_port((unsigned*)&p_txd->rmii_data_1b.data_0, 32);
            tx_data_1 = enable_buffered_out_port((unsigned*)&p_txd->rmii_data_1b.data_1, 32);
            rmii_master_init_tx_1b(p_clk, tx_data_0, tx_data_1, p_txen, txclk);
            break;
        default:
            fail("Invald port width for RMII Tx");
            break;
        }

        return {tx_port_width, tx_port_4b_pins, tx_data_0, tx_data_1};

    }
}


void rmii_ethernet_rt_mac(SERVER_INTERFACE(ethernet_cfg_if, i_cfg[n_cfg]), static_const_unsigned_t n_cfg,
                          SERVER_INTERFACE(ethernet_rx_if, i_rx_lp[n_rx_lp]), static_const_unsigned_t n_rx_lp,
                          SERVER_INTERFACE(ethernet_tx_if, i_tx_lp[n_tx_lp]), static_const_unsigned_t n_tx_lp,
                          nullable_streaming_chanend_t c_rx_hp,
                          nullable_streaming_chanend_t c_tx_hp,
                          in_port_t p_clk,
                          rmii_data_port_t * unsafe p_rxd, in_port_t p_rxdv,
                          out_port_t p_txen, rmii_data_port_t * unsafe p_txd,
                          clock rxclk,
                          clock txclk,
                          static_const_unsigned_t rx_bufsize_words,
                          static_const_unsigned_t tx_bufsize_words,
                          enum ethernet_enable_shaper_t enable_shaper)
{
  // Establish types of data ports presented
  unsafe{
    // Setup buffering
    unsigned int rx_data[rx_bufsize_words];
    unsigned int tx_data[tx_bufsize_words];
    mii_mempool_t rx_mem[1];
    mii_mempool_t * unsafe rx_mem_ptr = (mii_mempool_t *)rx_mem;


    rx_mem[0] = mii_init_mempool(rx_data, rx_bufsize_words*4);

    // If the high priority traffic is connected then allocate half the buffer for high priority
    // and half for low priority. Otherwise, allocate it all to low priority.
    const size_t lp_buffer_bytes = !isnull(c_tx_hp) ? tx_bufsize_words * 2 : tx_bufsize_words * 4;
    const size_t hp_buffer_bytes = tx_bufsize_words * 4 - lp_buffer_bytes;
    mii_mempool_t tx_mem_lp = mii_init_mempool(tx_data, lp_buffer_bytes);
    mii_mempool_t tx_mem_hp = mii_init_mempool(tx_data + (lp_buffer_bytes/4), hp_buffer_bytes);
    mii_mempool_t * unsafe tx_mem_lp_ptr = (mii_mempool_t *)&tx_mem_lp;
    mii_mempool_t * unsafe tx_mem_hp_ptr = (mii_mempool_t *)&tx_mem_hp;

    packet_queue_info_t rx_packets_lp, rx_packets_hp, tx_packets_lp, tx_packets_hp, incoming_packets;
    mii_init_packet_queue((mii_packet_queue_t)&rx_packets_lp);
    mii_init_packet_queue((mii_packet_queue_t)&rx_packets_hp);
    mii_init_packet_queue((mii_packet_queue_t)&tx_packets_lp);
    mii_init_packet_queue((mii_packet_queue_t)&tx_packets_hp);
    mii_init_packet_queue((mii_packet_queue_t)&incoming_packets);
    packet_queue_info_t * unsafe incoming_packets_ptr = &incoming_packets;
    packet_queue_info_t * unsafe rx_packets_lp_ptr = &rx_packets_lp;
    packet_queue_info_t * unsafe rx_packets_hp_ptr = &rx_packets_hp;
    packet_queue_info_t * unsafe tx_packets_lp_ptr = &tx_packets_lp;
    packet_queue_info_t * unsafe tx_packets_hp_ptr = &tx_packets_hp;

    // Shared read pointer to help optimize the RX code
    unsigned rx_rdptr = 0;
    mii_rdptr_t * unsafe p_rx_rdptr = (mii_rdptr_t*)&rx_rdptr;


    mii_init_lock();

    mii_ts_queue_entry_t ts_fifo[MII_TIMESTAMP_QUEUE_MAX_SIZE + 1];
    mii_ts_queue_info_t ts_queue_info;

    if (n_tx_lp > MII_TIMESTAMP_QUEUE_MAX_SIZE) {
      fail("Exceeded maximum number of transmit clients. Increase MII_TIMESTAMP_QUEUE_MAX_SIZE in ethernet_conf.h");
    }

    if (!ETHERNET_SUPPORT_HP_QUEUES && (!isnull(c_rx_hp) || !isnull(c_tx_hp))) {
      fail("Using high priority channels without #define ETHERNET_SUPPORT_HP_QUEUES set true");
    }

    mii_ts_queue_init(&ts_queue_info, ts_fifo, n_tx_lp + 1);
    mii_ts_queue_info_t * unsafe ts_queue_info_ptr = &ts_queue_info;


    // Common initialisation
    set_port_use_on(p_clk); // RMII 50MHz clock input port

    // Setup RX data ports
    // First declare C pointers for port resources and the initialise
    in buffered port:32 * unsafe rx_data_0 = NULL;
    in buffered port:32 * unsafe rx_data_1 = NULL;
    unsigned rx_port_width;
    rmii_data_4b_pin_assignment_t rx_port_4b_pins;
    {rx_port_width, rx_port_4b_pins, rx_data_0, rx_data_1} = init_rx_ports(p_clk, p_rxdv, rxclk, p_rxd);

    // Setup TX data ports
    // First declare C pointers for port resources and the initialise
    out buffered port:32 * unsafe tx_data_0 = NULL;
    out buffered port:32 * unsafe tx_data_1 = NULL;
    unsigned tx_port_width;
    rmii_data_4b_pin_assignment_t tx_port_4b_pins;
    {tx_port_width, tx_port_4b_pins, tx_data_0, tx_data_1} = init_tx_ports(p_clk, p_txen, txclk, p_txd);

    // Setup server
    ethernet_port_state_t port_state;
    init_server_port_state(port_state, enable_shaper == ETHERNET_ENABLE_SHAPER);

    ethernet_port_state_t * unsafe p_port_state = (ethernet_port_state_t * unsafe)&port_state;

    // Exit flag and chanend
    int rmii_ethernet_rt_mac_running = 1;
    int * unsafe running_flag_ptr = &rmii_ethernet_rt_mac_running;
    chan c_rx_pins_exit[1];

    chan c_conf;
    par {
      // Rx task
      {
        if(rx_port_width == 4){
          rmii_master_rx_pins_4b(rx_mem[0],
                                 (mii_packet_queue_t)&incoming_packets,
                                 (mii_rdptr_t)&rx_rdptr,
                                 p_rxdv,
                                 rx_data_0,
                                 rx_port_4b_pins,
                                 running_flag_ptr,
                                 c_rx_pins_exit[0]);
        } else {
          rmii_master_rx_pins_1b(rx_mem[0],
                                 (mii_packet_queue_t)&incoming_packets,
                                 (mii_rdptr_t)&rx_rdptr,
                                 p_rxdv,
                                 rx_data_0,
                                 rx_data_1,
                                 running_flag_ptr,
                                 c_rx_pins_exit[0]);
        }
      }
      // Tx task
      rmii_master_tx_pins(tx_mem_lp,
                          tx_mem_hp,
                          (mii_packet_queue_t)&tx_packets_lp,
                          (mii_packet_queue_t)&tx_packets_hp,
                          rx_mem_ptr,
                          rx_packets_lp_ptr,
                          rx_packets_hp_ptr,
                          &ts_queue_info,
                          tx_port_width,
                          tx_data_0,
                          tx_data_1,
                          tx_port_4b_pins,
                          txclk,
                          p_port_state,
                          0,
                          running_flag_ptr,
                          1);

      mii_ethernet_filter(c_conf,
                          incoming_packets_ptr,
                          rx_packets_lp_ptr,
                          rx_packets_hp_ptr,
                          running_flag_ptr,
                          1);

      mii_ethernet_server(rx_mem_ptr,
                          rx_packets_lp_ptr,
                          rx_packets_hp_ptr,
                          p_rx_rdptr,
                          tx_mem_lp_ptr,
                          tx_mem_hp_ptr,
                          tx_packets_lp_ptr,
                          tx_packets_hp_ptr,
                          ts_queue_info_ptr,
                          i_cfg, n_cfg,
                          i_rx_lp, n_rx_lp,
                          i_tx_lp, n_tx_lp,
                          c_rx_hp,
                          c_tx_hp,
                          c_conf,
                          p_port_state,
                          running_flag_ptr,
                          c_rx_pins_exit,
                          ETH_MAC_IF_RMII,
                          1);
    } // par

    // If exit occurred, disable used ports and resources so they are left in a good state
    mii_deinit_lock();

    stop_clock(rxclk);
    switch(rx_port_width){
      case 4:
        set_port_use_off(p_rxd->rmii_data_1b.data_0);
        break;
      case 1:
        set_port_use_off(p_rxd->rmii_data_1b.data_0);
        set_port_use_off(p_rxd->rmii_data_1b.data_1);
        break;
      default:
        fail("Invald port width for RMII Rx");
        break;
    }
    set_port_use_off(p_rxdv);

    stop_clock(txclk);
    switch(tx_port_width){
      case 4:
        set_port_use_off(p_txd->rmii_data_1b.data_0);
        break;
      case 1:
        set_port_use_off(p_txd->rmii_data_1b.data_0);
        set_port_use_off(p_txd->rmii_data_1b.data_1);
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


void rmii_ethernet_rt_mac_dual(SERVER_INTERFACE(ethernet_cfg_if, i_cfg[n_cfg]), static_const_unsigned_t n_cfg,
                              SERVER_INTERFACE(ethernet_rx_if, i_rx_lp[n_rx_lp]), static_const_unsigned_t n_rx_lp,
                              SERVER_INTERFACE(ethernet_tx_if, i_tx_lp[n_tx_lp]), static_const_unsigned_t n_tx_lp,
                              nullable_streaming_chanend_t c_rx_hp,
                              nullable_streaming_chanend_t c_tx_hp,
                              in_port_t p_clk,
                              rmii_data_port_t * unsafe p_rxd_0, in_port_t p_rxdv_0,
                              out_port_t p_txen_0, rmii_data_port_t * unsafe p_txd_0,
                              clock rxclk_0,
                              clock txclk_0,
                              rmii_data_port_t * unsafe p_rxd_1, in_port_t p_rxdv_1,
                              out_port_t p_txen_1, rmii_data_port_t * unsafe p_txd_1,
                              clock rxclk_1,
                              clock txclk_1,
                              static_const_unsigned_t rx_bufsize_words,
                              static_const_unsigned_t tx_bufsize_words,
                              enum ethernet_enable_shaper_t enable_shaper)
{
  // Establish types of data ports presented
    unsafe{
        // Setup buffering
        unsigned int rx_data[rx_bufsize_words ][2];
        unsigned int tx_data[tx_bufsize_words][2];
        mii_mempool_t rx_mem[2];
        mii_mempool_t * unsafe rx_mem_ptr = (mii_mempool_t *)rx_mem;
        for(int i=0; i<2; i++)
        {
          rx_mem[i] = mii_init_mempool(&rx_data[0][0] + i*rx_bufsize_words, rx_bufsize_words*4);
        }

        // If the high priority traffic is connected then allocate half the buffer for high priority
        // and half for low priority. Otherwise, allocate it all to low priority.
        const size_t lp_buffer_bytes = !isnull(c_tx_hp) ? tx_bufsize_words * 2 : tx_bufsize_words * 4;
        const size_t hp_buffer_bytes = tx_bufsize_words * 4 - lp_buffer_bytes;

        mii_mempool_t tx_mem_lp[2], tx_mem_hp[2];
        for(int i=0; i<2; i++)
        {
          tx_mem_lp[i] = mii_init_mempool(&tx_data[0][0] + i*((lp_buffer_bytes/4) + (hp_buffer_bytes/4)), lp_buffer_bytes);
          tx_mem_hp[i] = mii_init_mempool(&tx_data[0][0] + i*((lp_buffer_bytes/4) + (hp_buffer_bytes/4)) + (lp_buffer_bytes/4), hp_buffer_bytes);
        }
        mii_mempool_t * unsafe tx_mem_lp_ptr = (mii_mempool_t *)tx_mem_lp;
        mii_mempool_t * unsafe tx_mem_hp_ptr = (mii_mempool_t *)tx_mem_hp;

        packet_queue_info_t rx_packets_lp[2], rx_packets_hp[2], incoming_packets[2];
        packet_queue_info_t tx_packets_lp[2], tx_packets_hp[2];

        packet_queue_info_t * unsafe incoming_packets_ptr = incoming_packets;
        packet_queue_info_t * unsafe rx_packets_lp_ptr = rx_packets_lp;
        packet_queue_info_t * unsafe rx_packets_hp_ptr = rx_packets_hp;
        packet_queue_info_t * unsafe tx_packets_lp_ptr = tx_packets_lp;
        packet_queue_info_t * unsafe tx_packets_hp_ptr = tx_packets_hp;

        for(int i=0; i<2; i++)
        {
          mii_init_packet_queue((mii_packet_queue_t)&incoming_packets[i]);
          mii_init_packet_queue((mii_packet_queue_t)&rx_packets_lp[i]);
          mii_init_packet_queue((mii_packet_queue_t)&rx_packets_hp[i]);
          mii_init_packet_queue((mii_packet_queue_t)&tx_packets_lp[i]);
          mii_init_packet_queue((mii_packet_queue_t)&tx_packets_hp[i]);
        }


        // Shared read pointer to help optimize the RX code
        unsigned rx_rdptr[2] = {0};
        mii_rdptr_t * unsafe p_rx_rdptr = (mii_rdptr_t *)rx_rdptr; // Array of pointers


        mii_init_lock();
        mii_ts_queue_entry_t ts_fifo[2][MII_TIMESTAMP_QUEUE_MAX_SIZE + 1];
        mii_ts_queue_info_t ts_queue_info[2];

        if (n_tx_lp > MII_TIMESTAMP_QUEUE_MAX_SIZE) {
            fail("Exceeded maximum number of transmit clients. Increase MII_TIMESTAMP_QUEUE_MAX_SIZE in ethernet_conf.h");
        }

        if (!ETHERNET_SUPPORT_HP_QUEUES && (!isnull(c_rx_hp) || !isnull(c_tx_hp))) {
            fail("Using high priority channels without #define ETHERNET_SUPPORT_HP_QUEUES set true");
        }

        for(int i=0; i<2; i++)
        {
          mii_ts_queue_init(&ts_queue_info[i], ts_fifo[i], n_tx_lp + 1);
        }
        mii_ts_queue_info_t * unsafe ts_queue_info_ptr = ts_queue_info;




        // Common initialisation
        set_port_use_on(p_clk); // RMII 50MHz clock input port

        // Setup RX data ports
        // First declare C pointers for port resources and the initialise
        // MAC port 0
        in buffered port:32 * unsafe rx_data_0_0 = NULL;
        in buffered port:32 * unsafe rx_data_0_1 = NULL;
        unsigned rx_port_width_0;
        rmii_data_4b_pin_assignment_t rx_port_4b_pins_0;
        {rx_port_width_0, rx_port_4b_pins_0, rx_data_0_0, rx_data_0_1} = init_rx_ports(p_clk, p_rxdv_0, rxclk_0, p_rxd_0);
        // MAC port 1
        in buffered port:32 * unsafe rx_data_1_0 = NULL;
        in buffered port:32 * unsafe rx_data_1_1 = NULL;
        unsigned rx_port_width_1 = 0;
        rmii_data_4b_pin_assignment_t rx_port_4b_pins_1;
        {rx_port_width_1, rx_port_4b_pins_1, rx_data_1_0, rx_data_1_1} = init_rx_ports(p_clk, p_rxdv_1, rxclk_1, p_rxd_1);



        // Setup TX data ports
        // First declare C pointers for port resources and the initialise
        // MAC port 0
        out buffered port:32 * unsafe tx_data_0_0 = NULL;
        out buffered port:32 * unsafe tx_data_0_1 = NULL;
        unsigned tx_port_width_0;
        rmii_data_4b_pin_assignment_t tx_port_4b_pins_0;
        {tx_port_width_0, tx_port_4b_pins_0, tx_data_0_0, tx_data_0_1} = init_tx_ports(p_clk, p_txen_0, txclk_0, p_txd_0);
        // MAC port 1
        out buffered port:32 * unsafe tx_data_1_0 = NULL;
        out buffered port:32 * unsafe tx_data_1_1 = NULL;
        unsigned tx_port_width_1;
        rmii_data_4b_pin_assignment_t tx_port_4b_pins_1;
        {tx_port_width_1, tx_port_4b_pins_1, tx_data_1_0, tx_data_1_1} = init_tx_ports(p_clk, p_txen_1, txclk_1, p_txd_1);

        // Setup server
        ethernet_port_state_t port_state[2];

        for(int i=0; i<2; i++)
        {
          init_server_port_state(port_state[i], enable_shaper == ETHERNET_ENABLE_SHAPER);
        }

        ethernet_port_state_t * unsafe p_port_state = (ethernet_port_state_t * unsafe)port_state;

        // Exit flag and chanend
        int rmii_ethernet_rt_mac_running = 1;
        int * unsafe running_flag_ptr = &rmii_ethernet_rt_mac_running;
        chan c_rx_pins_exit[2];

        chan c_conf;
        par
        {
            {
                if(rx_port_width_0 == 4)
                {
                    rmii_master_rx_pins_4b(rx_mem[0],
                                          (mii_packet_queue_t)(&incoming_packets[0]),
                                          (mii_rdptr_t)&rx_rdptr[0],
                                          p_rxdv_0,
                                          rx_data_0_0,
                                          rx_port_4b_pins_0,
                                          running_flag_ptr,
                                          c_rx_pins_exit[0]);
                } else {
                    rmii_master_rx_pins_1b(rx_mem[0],
                                          (mii_packet_queue_t)(&incoming_packets[0]),
                                          (mii_rdptr_t)&rx_rdptr[0],
                                          p_rxdv_0,
                                          rx_data_0_0,
                                          rx_data_0_1,
                                          running_flag_ptr,
                                          c_rx_pins_exit[0]);
                }
            }
            {
                if(rx_port_width_1 == 4)
                {
                    rmii_master_rx_pins_4b(rx_mem[1],
                                          (mii_packet_queue_t)(&incoming_packets[1]),
                                          (mii_rdptr_t)&rx_rdptr[1],
                                          p_rxdv_1,
                                          rx_data_1_0,
                                          rx_port_4b_pins_1,
                                          running_flag_ptr,
                                          c_rx_pins_exit[1]);
                } else {
                    rmii_master_rx_pins_1b(rx_mem[1],
                                         (mii_packet_queue_t)(&incoming_packets[1]),
                                         (mii_rdptr_t)&rx_rdptr[1],
                                         p_rxdv_1,
                                         rx_data_1_0,
                                         rx_data_1_1,
                                         running_flag_ptr,
                                         c_rx_pins_exit[1]);
                }
            }
            rmii_master_tx_pins(tx_mem_lp[0],
                              tx_mem_hp[0],
                              (mii_packet_queue_t)(&tx_packets_lp[0]),
                              (mii_packet_queue_t)(&tx_packets_hp[0]),
                              rx_mem_ptr, // memory pool for the forwarding packets
                              rx_packets_lp_ptr, // lp forwarding packets queue
                              rx_packets_hp_ptr, // hp forwarding packets queue
                              (mii_ts_queue_t)&ts_queue_info[0],
                              tx_port_width_0,
                              tx_data_0_0,
                              tx_data_0_1,
                              tx_port_4b_pins_0,
                              txclk_0,
                              &p_port_state[0],
                              0,
                              running_flag_ptr,
                              2);

            rmii_master_tx_pins(tx_mem_lp[1],
                              tx_mem_hp[1],
                              (mii_packet_queue_t)(&tx_packets_lp[1]),
                              (mii_packet_queue_t)(&tx_packets_hp[1]),
                              rx_mem_ptr, // memory pool for the forwarding packets
                              rx_packets_lp_ptr, // lp forwarding packets queue
                              rx_packets_hp_ptr, // hp forwarding packets queue
                              (mii_ts_queue_t)&ts_queue_info[1],
                              tx_port_width_1,
                              tx_data_1_0,
                              tx_data_1_1,
                              tx_port_4b_pins_1,
                              txclk_1,
                              &p_port_state[1],
                              1,
                              running_flag_ptr,
                              2);


            mii_ethernet_filter(c_conf,
                              incoming_packets_ptr,
                              rx_packets_lp_ptr,
                              rx_packets_hp_ptr,
                              running_flag_ptr,
                              2);

            mii_ethernet_server(rx_mem_ptr,
                              rx_packets_lp_ptr,
                              rx_packets_hp_ptr,
                              p_rx_rdptr,
                              tx_mem_lp_ptr,
                              tx_mem_hp_ptr,
                              tx_packets_lp_ptr,
                              tx_packets_hp_ptr,
                              ts_queue_info_ptr,
                              i_cfg, n_cfg,
                              i_rx_lp, n_rx_lp,
                              i_tx_lp, n_tx_lp,
                              c_rx_hp,
                              c_tx_hp,
                              c_conf,
                              p_port_state,
                              running_flag_ptr,
                              c_rx_pins_exit,
                              ETH_MAC_IF_RMII,
                              2);
        } // par
    } // unsafe block
}

