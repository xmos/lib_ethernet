#include <xs1.h>
#include "ethernet.h"
#include "rgmii.h"
#include "rgmii_common.h"
#include "rgmii_10_100_master.h"
#include "rgmii_buffering.h"
#include "macaddr_filter_hash.h"

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

void rgmii_ethernet_mac(server ethernet_cfg_if i_cfg[n_cfg], static const unsigned n_cfg,
                        server ethernet_rx_if i_rx_lp[n_rx_lp], static const unsigned n_rx_lp,
                        server ethernet_tx_if i_tx_lp[n_tx_lp], static const unsigned n_tx_lp,
                        streaming chanend ? c_rx_hp,
                        streaming chanend ? c_tx_hp,
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
                        clock txclk_out)
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

  rx_client_state_t rx_client_state_lp[n_rx_lp];
  tx_client_state_t tx_client_state_lp[n_tx_lp];

  init_rx_client_state(rx_client_state_lp, n_rx_lp);
  init_tx_client_state(tx_client_state_lp, n_tx_lp);

  mii_macaddr_hash_table_init();

  mii_init_lock();

  unsafe {
    unsigned int buffer_rx[RGMII_MAC_BUFFER_COUNT_RX * sizeof(mii_packet_t) / 4];
    unsigned int buffer_free_pointers_rx[RGMII_MAC_BUFFER_COUNT_RX];
    unsigned int buffer_used_pointers_rx_lp[RGMII_MAC_BUFFER_COUNT_RX + 1];
    unsigned int buffer_used_pointers_rx_hp[RGMII_MAC_BUFFER_COUNT_RX + 1];
    buffers_used_t used_buffers_rx_lp;
    buffers_used_t used_buffers_rx_hp;
    buffers_free_t free_buffers_rx;

    unsigned int buffer_tx[RGMII_MAC_BUFFER_COUNT_TX * sizeof(mii_packet_t) / 4];
    unsigned int buffer_free_pointers_tx[RGMII_MAC_BUFFER_COUNT_RX];
    unsigned int buffer_used_pointers_tx[RGMII_MAC_BUFFER_COUNT_RX + 1];
    buffers_used_t used_buffers_tx;
    buffers_free_t free_buffers_tx;

    // Create unsafe pointers to pass to two parallel tasks
    buffers_used_t * unsafe p_used_buffers_rx_lp = &used_buffers_rx_lp;
    buffers_used_t * unsafe p_used_buffers_rx_hp = &used_buffers_rx_hp;
    buffers_free_t * unsafe p_free_buffers_rx = &free_buffers_rx;
    in buffered port:32 * unsafe p_rxd_1000 = &p_rxd_1000_safe;
    in port * unsafe p_rxdv_unsafe = &p_rxdv;
    in buffered port:1 * unsafe p_rxer_unsafe = &p_rxer_safe;
    rx_client_state_t * unsafe p_rx_client_state_lp = (rx_client_state_t * unsafe)&rx_client_state_lp[0];

    streaming chan c_rx_to_manager[2], c_manager_to_tx, c_ping_pong, c_status_update;
    streaming chanend * unsafe c_speed_change;
    int speed_change_ids[8];
    rgmii_inband_status_t current_mode = INITIAL_MODE;

    rgmii_configure_ports(p_rxclk, p_rxer_safe, p_rxd_1000_safe, p_rxd_10_100,
                          p_rxd_interframe, p_rxdv, p_rxdv_interframe,
                          p_txclk_in, p_txclk_out, p_txer, p_txen, p_txd,
                          rxclk, rxclk_interframe, txclk, txclk_out);

    log_speed_change_pointers(speed_change_ids);
    c_speed_change = (streaming chanend * unsafe)speed_change_ids;

    while(1)
    {
      // Setup the buffer pointers
      buffers_used_initialize(used_buffers_rx_lp, buffer_used_pointers_rx_lp);
      buffers_used_initialize(used_buffers_rx_hp, buffer_used_pointers_rx_hp);
      buffers_free_initialize(free_buffers_rx, (unsigned char*)buffer_rx,
                              buffer_free_pointers_rx, RGMII_MAC_BUFFER_COUNT_RX);

      buffers_used_initialize(used_buffers_tx, buffer_used_pointers_tx);
      buffers_free_initialize(free_buffers_tx, (unsigned char*)buffer_tx,
                              buffer_free_pointers_tx, RGMII_MAC_BUFFER_COUNT_TX);

      if (current_mode == INBAND_STATUS_1G_FULLDUPLEX)
      {
        mii_macaddr_set_num_active_filters(2);
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
              {
                rgmii_buffer_manager(c_rx_to_manager[0], c_speed_change[3],
                                     *p_used_buffers_rx_lp, *p_used_buffers_rx_hp, *p_free_buffers_rx, 0);
              }
              {
                rgmii_buffer_manager(c_rx_to_manager[1], c_speed_change[4],
                                     *p_used_buffers_rx_lp, *p_used_buffers_rx_hp, *p_free_buffers_rx, 1);
              }
            }
          }

          {
            rgmii_ethernet_rx_server_aux((rx_client_state_t *)p_rx_client_state_lp, i_rx_lp, n_rx_lp,
                                         c_rx_hp, c_status_update,
                                         c_speed_change[5], p_txclk_out, p_rxd_interframe,
                                         *p_used_buffers_rx_lp, *p_used_buffers_rx_hp,
                                         *p_free_buffers_rx, current_mode);
            current_mode = get_current_rgmii_mode(p_rxd_interframe);
          }

          {
            rgmii_ethernet_tx_server_aux(tx_client_state_lp, i_tx_lp, n_tx_lp,
                                         c_tx_hp,
                                         c_manager_to_tx, c_speed_change[6],
                                         used_buffers_tx, free_buffers_tx);
          }
          {
            rgmii_ethernet_config_server_aux((rx_client_state_t *)p_rx_client_state_lp, n_rx_lp,
                                             i_cfg, n_cfg, c_status_update, c_speed_change[7]);
          }
        }
      }
      else if (current_mode == INBAND_STATUS_100M_FULLDUPLEX ||
               current_mode == INBAND_STATUS_10M_FULLDUPLEX)
      {
        mii_macaddr_set_num_active_filters(1);

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
                rgmii_buffer_manager(c_rx_to_manager[0], c_speed_change[3],
                                     *p_used_buffers_rx_lp, *p_used_buffers_rx_hp, *p_free_buffers_rx, 0);
              }
              {
                // Just wait for a change from 100Mb mode and empty those channels
                c_speed_change[2] :> unsigned tmp;
                c_speed_change[4] :> unsigned tmp;
              }
            }
          }

          {
            rgmii_ethernet_rx_server_aux((rx_client_state_t *)p_rx_client_state_lp, i_rx_lp, n_rx_lp,
                                         c_rx_hp, c_status_update,
                                         c_speed_change[5], p_txclk_out, p_rxd_interframe,
                                         *p_used_buffers_rx_lp, *p_used_buffers_rx_hp,
                                         *p_free_buffers_rx, current_mode);
            current_mode = get_current_rgmii_mode(p_rxd_interframe);
          }

          {
            rgmii_ethernet_tx_server_aux(tx_client_state_lp, i_tx_lp, n_tx_lp,
                                         c_tx_hp,
                                         c_manager_to_tx, c_speed_change[6],
                                         used_buffers_tx, free_buffers_tx);
          }
          {
            rgmii_ethernet_config_server_aux((rx_client_state_t *)p_rx_client_state_lp, n_rx_lp,
                                             i_cfg, n_cfg, c_status_update, c_speed_change[7]);
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
