#include <xs1.h>
#include <platform.h>
#include <stdlib.h>
#include <xscope.h>
#include <string.h>
#include <assert.h>
#include "debug_print.h"
#include "ethernet.h"
#include "xscope_cmd_handler.h"
#include "xscope_control.h"

static void wait_us(int microseconds)
{
    timer t;
    unsigned time;

    t :> time;
    t when timerafter(time + (microseconds * 100)) :> void;
}

select xscope_cmd_handler(chanend c_xscope_control, client_cfg_t &client_cfg, client ethernet_cfg_if cfg, client_state_t &client_state)
{
  case c_xscope_control :> int cmd: // Shutdown received over xscope
    if(cmd == CMD_DEVICE_CONNECT)
    {
      debug_printf("client %d received command CMD_DEVICE_CONNECT\n", client_cfg.client_num);
      if(client_cfg.client_num == 0)
      {
        // The first client needs to ensure link is up when returning ready status
        unsigned link_state, link_speed;
        cfg.get_link_state(0, link_state, link_speed);
        while(link_state != ETHERNET_LINK_UP)
        {
          wait_us(1000); // Check every 1ms
          cfg.get_link_state(0, link_state, link_speed);
        }
        debug_printf("Ethernet link up\n");
      }
      c_xscope_control <: 1; // Indicate ready
    }
    else if(cmd == CMD_DEVICE_SHUTDOWN)
    {
      client_state.done = 1;
    }
    else if(cmd == CMD_SET_DEVICE_MACADDR)
    {
      debug_printf("Received CMD_SET_DEVICE_MACADDR command\n");
      ethernet_macaddr_filter_t macaddr_filter;
      for(int i=0; i<MACADDR_NUM_BYTES; i++)
      {
        c_xscope_control :> macaddr_filter.addr[i];
        client_state.source_mac_addr[i] = macaddr_filter.addr[i];
        if(client_cfg.is_hp)
        {
            cfg.add_macaddr_filter(0, 1, macaddr_filter); // TODO - Do this only for RX. Maybe CMD_SET_DEVICE_MACADDR and CMD_SET_DEVICE_MACADDR_FILTER need to be separate commands??
        }
        else
        {
            cfg.add_macaddr_filter(client_cfg.client_index, 0, macaddr_filter); // TODO - Do this only for RX
        }

      }
      c_xscope_control <: 1; // Acknowledge
    }
    else if(cmd == CMD_SET_HOST_MACADDR)
    {
      debug_printf("Received CMD_SET_HOST_MACADDR command\n");
      for(int i=0; i<MACADDR_NUM_BYTES; i++)
      {
        c_xscope_control :> client_state.target_mac_addr[i];
      }
      c_xscope_control <: 1; // Acknowledge
    }
    else if(cmd == CMD_HOST_SET_DUT_TX_PACKETS)
    {
        if(client_cfg.is_hp)
        {
            c_xscope_control :> client_state.qav_bw_bps;
            c_xscope_control :> client_state.tx_packet_len;
            debug_printf("Received CMD_HOST_SET_DUT_TX_PACKETS command. bandwidth_bps = %d\n", client_state.qav_bw_bps);

            if(client_state.qav_bw_bps)
            {
                cfg.set_egress_qav_idle_slope_bps(0, client_state.qav_bw_bps);
            }
        }
        else
        {
            c_xscope_control :> client_state.num_tx_packets;
            c_xscope_control :> client_state.tx_packet_len;
            debug_printf("Received CMD_HOST_SET_DUT_TX_PACKETS command. num_packets = %d\n", client_state.num_tx_packets);
        }

        c_xscope_control <: 1; // Acknowledge
    }
    else if(cmd == CMD_SET_DUT_RECEIVE)
    {
      c_xscope_control :> client_state.receiving;
      c_xscope_control <: 1; // Acknowledge
    }
    else if(cmd == CMD_EXIT_DEVICE_MAC)
    {
      debug_printf("Received CMD_EXIT_DEVICE_MAC command\n");
      cfg.exit();
      // the client is expected to exit after signalling the Mac to exit
      client_state.done = 1;
    }
    break;

}
