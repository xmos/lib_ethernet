#include <xs1.h>
#include "ethernet.h"
#include "rgmii.h"
#include "rgmii_common.h"
#include "rgmii_10_100_master.h"
#include "rgmii_buffering.h"

rgmii_inband_status_t get_current_rgmii_mode(in buffered port:4 p_rxd_interframe)
{
  // Ensure that the data returned is the current value
  clearbuf(p_rxd_interframe);
  rgmii_inband_status_t mode = partin(p_rxd_interframe, 4);
  return mode;
}

void rgmii_configure_ports(in port p_rxclk, in buffered port:1 p_rxer,
                           in buffered port:32 p_rxd_1000, in buffered port:32 p_rxd_10_100,
                           in buffered port:4 p_rxd_interframe,
                           in port p_rxdv, in port p_rxdv_interframe,
                           in port p_txclk_in, out port p_txclk_out, 
                           out port p_txer, out port p_txen,
                           out buffered port:32 p_txd,
                           clock rxclk,
                           clock rxclk_interframe,
                           clock txclk,
                           clock txclk_out)
{
  // Configure the ports for 1G
  configure_clock_src(rxclk, p_rxclk);
  configure_in_port_strobed_slave(p_rxd_1000, p_rxdv, rxclk);
  configure_in_port_strobed_slave(p_rxd_10_100, p_rxdv, rxclk);

  // Configure port used to read the data when DV is low
  configure_clock_src(rxclk_interframe, p_rxclk);
  set_port_inv(p_rxdv_interframe);
  configure_in_port_strobed_slave(p_rxd_interframe, p_rxdv_interframe, rxclk_interframe);

  // Configure the TX ports
  configure_clock_src(txclk, p_txclk_in);
  configure_out_port_strobed_master(p_txd, p_txen, txclk, 0);
  configure_out_port(p_txer, txclk, 0);
  
  set_clock_fall_delay(txclk, 2);
  set_clock_rise_delay(txclk, 2);
  set_clock_rise_delay(rxclk, 0);
  set_clock_fall_delay(rxclk_interframe, 3);
  set_clock_rise_delay(rxclk_interframe, 3);

  // Ensure that the error port is running fast enough to catch errors
  configure_in_port(p_rxer, rxclk);
  
  configure_clock_src(txclk_out, p_txclk_in);
  configure_port_clock_output(p_txclk_out, txclk_out);
  set_port_inv(p_txclk_out);

  // Use this to align the data recived by the rgmii block with TXC, 
  // only require the data to arrive before the edge that it should be 
  // output on but after the TXC last edge. 
  // At 500MHz, data arrives in slot 3 i.e 2 cycles before tx rising edge
  set_clock_fall_delay(txclk_out, 3);
  set_clock_rise_delay(txclk_out, 3);

  // Start the clocks
  start_clock(txclk);
  start_clock(txclk_out);
  start_clock(rxclk);
  start_clock(rxclk_interframe);
}

void rgmii_ethernet_mac(server ethernet_if i_eth[n], static const unsigned n,
                        in port p_rxclk, in port _p_rxer,
                        in port _p_rxd_1000, in port _p_rxd_10_100,
                        in port _p_rxd_interframe,
                        in port p_rxdv, in port p_rxdv_interframe,
                        in port p_txclk_in, out port p_txclk_out, 
                        out port p_txer, out port p_txen,
                        out port _p_txd,
                        clock rxclk,
                        clock rxclk_interframe,
                        clock txclk,
                        clock txclk_out,
                        static const unsigned bufsize_words)
{
  in port * movable _pp_rxd_1000 = &_p_rxd_1000;
  in buffered port:32 * movable pp_rxd_1000 = reconfigure_port(move(_pp_rxd_1000), in buffered port:32);
  in buffered port:32 &p_rxd_1000_safe = *pp_rxd_1000;
  in port * movable _pp_rxd_10_100 = &_p_rxd_10_100;
  in buffered port:32 * movable pp_rxd_10_100 = reconfigure_port(move(_pp_rxd_10_100), in buffered port:32);
  in buffered port:32 &p_rxd_10_100 = *pp_rxd_10_100;
  in port * movable _pp_rxd_interframe = &_p_rxd_interframe;
  in buffered port:4 * movable pp_rxd_interframe = reconfigure_port(move(_pp_rxd_interframe), in buffered port:4);
  in buffered port:4 &p_rxd_interframe = *pp_rxd_interframe;
  out port * movable _pp_txd = &_p_txd;
  out buffered port:32 * movable pp_txd = reconfigure_port(move(_pp_txd), out buffered port:32);
  out buffered port:32 &p_txd = *pp_txd;
  in port * movable _pp_rxer = &_p_rxer;
  in buffered port:1 * movable pp_rxer = reconfigure_port(move(_pp_rxer), in buffered port:1);
  in buffered port:1 &p_rxer_safe = *pp_rxer;
  unsafe {
    unsigned int buffer[bufsize_words];
    buffers_used_t used_buffers;
    buffers_free_t free_buffers;
    in buffered port:32 *unsafe p_rxd_1000 = &p_rxd_1000_safe;
    in port *unsafe p_rxdv_unsafe = &p_rxdv;
    in buffered port:1 *unsafe p_rxer_unsafe = &p_rxer_safe;
    streaming chan c_rx_to_manager[2], c_manager_to_tx, c_ping_pong;
    streaming chanend * unsafe c_speed_change;
    int speed_change_ids[4];
    rgmii_inband_status_t current_mode = INITIAL_MODE;

    rgmii_configure_ports(p_rxclk, p_rxer_safe, p_rxd_1000_safe, p_rxd_10_100, p_rxd_interframe, p_rxdv, p_rxdv_interframe,
                          p_txclk_in, p_txclk_out, p_txer, p_txen, p_txd, rxclk, rxclk_interframe, txclk, txclk_out);  

    log_speed_change_pointers(speed_change_ids);
    c_speed_change = (streaming chanend * unsafe)speed_change_ids;

    while(1)
    {
      if (current_mode == INBAND_STATUS_1G_FULLDUPLEX)
      {
        par
        {
          {
            rgmii_tx_lld(c_manager_to_tx, p_txd, c_speed_change[0]);
            empty_channel(c_manager_to_tx);
          }

          {
            clearbuf(*p_rxd_1000);
            par {
              {
                rgmii_rx_lld(c_rx_to_manager[0], c_ping_pong, 0, c_speed_change[1],
			     *p_rxd_1000, *p_rxdv_unsafe, *p_rxer_unsafe);
                empty_channel(c_rx_to_manager[0]);
                empty_channel(c_ping_pong);
              }
              {
                rgmii_rx_lld(c_rx_to_manager[1], c_ping_pong, 1, c_speed_change[2],
			     *p_rxd_1000, *p_rxdv_unsafe, *p_rxer_unsafe);
                empty_channel(c_rx_to_manager[1]);
                empty_channel(c_ping_pong);
              }
            }
          }

          {
            // Setup the buffer pointers
            buffers_used_initialise(used_buffers);
            buffers_free_initialise(free_buffers, (unsigned char*)buffer);

            unsigned int error = 0;
            error = buffer_manager_1000(c_rx_to_manager[0], c_rx_to_manager[1], c_manager_to_tx,
                                        c_speed_change[3], p_txclk_out, p_rxd_interframe,
                                        used_buffers, free_buffers, current_mode);
            current_mode = get_current_rgmii_mode(p_rxd_interframe);
            if (error)
              __builtin_trap();
          }
        }
      }
      else if (current_mode == INBAND_STATUS_100M_FULLDUPLEX ||
               current_mode == INBAND_STATUS_10M_FULLDUPLEX)
      {
        par
        {
          {
            rgmii_10_100_master_tx_pins(c_manager_to_tx, p_txd, c_speed_change[0]);
            empty_channel(c_manager_to_tx);
          }

          {
            clearbuf(p_rxd_10_100);
            par {
              {
                rgmii_10_100_master_rx_pins(c_rx_to_manager[0], p_rxd_10_100, p_rxdv,
					    p_rxer_safe, c_speed_change[1]);
                empty_channel(c_rx_to_manager[0]);
              }
              {
                // Just wait for a change from 100Mb mode
                c_speed_change[2] :> unsigned tmp;
              }
            }
          }

          {
            // Setup the buffer pointers
            buffers_used_initialise(used_buffers);
            buffers_free_initialise(free_buffers, (unsigned char*)buffer);

            unsigned int error = 0;
            error = buffer_manager_10_100(c_rx_to_manager[0], c_manager_to_tx,
                                          c_speed_change[3], p_txclk_out, p_rxd_interframe,
                                          used_buffers, free_buffers, current_mode);
            current_mode = get_current_rgmii_mode(p_rxd_interframe);
            if (error)
              __builtin_trap();
          }
        }
      }
      else
      {
        // Unrecognized speed - re-read the value
        current_mode = get_current_rgmii_mode(p_rxd_interframe);
      }
    }
  }

}
