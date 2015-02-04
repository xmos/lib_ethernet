#ifndef __ethernet__h__
#define __ethernet__h__
#include <xs1.h>
#include <stdint.h>
#include <stddef.h>
#include "ethernet_defines.h"

/** Type representing the type of packet from the MAC */
typedef enum eth_packet_type_t {
  ETH_DATA,                      /**< A packet containing data. */
  ETH_IF_STATUS,                 /**< A control packet containing interface status information */
  ETH_OUTGOING_TIMESTAMP_INFO,   /**< A control packet containing an outgoing timestamp */
  ETH_NO_DATA                    /**< A packet containing no data. */
} eth_packet_type_t;

#define ETHERNET_ALL_INTERFACES  (-1)

/** Type representing link events. */
typedef enum ethernet_link_state_t {
  ETHERNET_LINK_DOWN,    /**< Ethernet link down event. */
  ETHERNET_LINK_UP       /**< Ethernet link up event. */
} ethernet_link_state_t;

typedef struct ethernet_packet_info_t {
  eth_packet_type_t type;
  unsigned len;
  unsigned timestamp;
  unsigned src_ifnum;
  unsigned filter_data;
} ethernet_packet_info_t;

typedef struct ethernet_macaddr_filter_t {
  unsigned char addr[6];
  unsigned appdata;
} ethernet_macaddr_filter_t;

typedef enum ethernet_macaddr_filter_result_t {
  ETHERNET_MACADDR_FILTER_SUCCESS,
  ETHERNET_MACADDR_FILTER_TABLE_FULL
} ethernet_macaddr_filter_result_t;

#ifdef __XC__

/** Ethernet endpoint configuration interface.
 *
 *  This interface allows clients to configure the ethernet endpoint. */
typedef interface ethernet_cfg_if {
  void set_macaddr(size_t ifnum, unsigned char mac_address[6]);

  void get_macaddr(size_t ifnum, unsigned char mac_address[6]);

  /** Set the current link state.
   *
   *  This function sets the current link state of the interface component.
   *
   *  \param portnum   The port number of the ethernet link changing state.
   *                   For single port ethernet instances this should be
   *                   set to 0.
   *  \param new_state The new link state for the port.
   */
  void set_link_state(int ifnum, ethernet_link_state_t new_state);

  /** Add MAC addresses to the filter.
   *
   *  \param client_num   The index into the set of rx clients. Can be acquired by
   *                      calling the get_index() method.
   *  \param is_hp        Indicates whether the rx client is high priority. There is
   *                      only 1 high priority client, so client_num must be 0 when
   *                      is_hp is set.
   *  \param entry        The filter entry to add.
   *
   *  \returns            ETHERNET_MACADDR_FILTER_SUCCESS when the entry is added or
   *                      ETHERNET_MACADDR_FILTER_TABLE_FULL on failure.
   *
   */
  ethernet_macaddr_filter_result_t
    add_macaddr_filter(size_t client_num, int is_hp, ethernet_macaddr_filter_t entry);

  void del_macaddr_filter(size_t client_num, int is_hp, ethernet_macaddr_filter_t entry);

  void del_all_macaddr_filters(size_t client_num, int is_hp);

  void add_ethertype_filter(size_t client_num, int is_hp, uint16_t ethertype);
  void del_ethertype_filter(size_t client_num, int is_hp, uint16_t ethertype);

  void get_tile_id_and_timer_value(unsigned &tile_id, unsigned &time_on_tile);

  void set_tx_qav_idle_slope(unsigned slope);

} ethernet_cfg_if;

/** Ethernet endpoint receive interface.
 *
 *  This interface allows clients to send and receive packets. */
typedef interface ethernet_tx_if {
  void _init_send_packet(size_t n, size_t ifnum);
  void _complete_send_packet(char packet[n], unsigned n,
                             int request_timestamp, size_t ifnum);

  unsigned _get_outgoing_timestamp();
} ethernet_tx_if;

/** Ethernet endpoint receive interface.
 *
 *  This interface allows clients to send and receive packets. */
typedef interface ethernet_rx_if {
  /** Get the index of a given receiver
   *
   */
  size_t get_index();

  [[notification]] slave void packet_ready();
  [[clears_notification]] void get_packet(ethernet_packet_info_t &desc,
                                          char data[n],
                                          unsigned n);
} ethernet_rx_if;

/** Function to receive a packet over a high priority channel
 *
 * The packet can be split into two transactions due to internal buffering
 * and therefore this function must be used to receive the packet.
 *
 */
inline void mii_receive_hp_packet(streaming chanend c_rx_hp,
                                  unsigned char *buf,
                                  ethernet_packet_info_t &packet_info)
{
  unsigned len1 = packet_info.len & 0xffff;
  sin_char_array(c_rx_hp, buf, len1);
  unsigned len2 = packet_info.len >> 16;
  if (len2) {
    sin_char_array(c_rx_hp, &buf[len1], len2);
  }
  packet_info.len = len1 + len2;
}

extends client interface ethernet_tx_if : {

  inline void send_packet(client ethernet_tx_if i, char packet[n], unsigned n,
                          unsigned dst_port) {
    i._init_send_packet(n, dst_port);
    i._complete_send_packet(packet, n, 0, dst_port);
  }

  inline unsigned send_timed_packet(client ethernet_tx_if i, char packet[n],
                                    unsigned n,
                                    unsigned dst_port) {
    i._init_send_packet(n, dst_port);
    i._complete_send_packet(packet, n, 1, dst_port);
    return i._get_outgoing_timestamp();
  }
}

enum ethernet_enable_shaper_t {
  ETHERNET_ENABLE_SHAPER,
  ETHERNET_DISABLE_SHAPER
};

/** Ethernet component to connect to an RGMII interface
 *
 *  This function implements an ethernet component connected to an RGMII
 *  interface.
 *  Interaction to the component is via the connected filtering, configuration
 *  and data interfaces.
 *
 *  \param i_cfg              Array of client configuration interfaces
 *  \param n_cfg              The number of configuration clients connected
 *
 *  \param i_rx_lp            Array of low priority receive clients
 *  \param n_rx_lp            The number of low priority receive clients connected
 *
 *  \param i_tx_lp            Array of low priority transmit clients
 *  \param n_tx_lp            The number of low priority transmit clients connected
 *
 *  \param c_rx_hp            Streaming channel end for high priority receive data
 *  \param c_tx_hp            Streaming channel end for high priority transmit data
 *
 *  \param p_rxclk            RX clock port
 *  \param p_rxer             RX error port
 *  \param p_rxd_1000         1Gb RX data port
 *  \param p_rxd_10_100       10/100Mb RX data port
 *  \param p_rxd_interframe   Interframe RX data port
 *  \param p_rxdv             RX data valid port
 *  \param p_rxdv_interframe  Interframe RX data valid port
 *  \param p_txclk_in         TX clock input port
 *  \param p_txclk_out        TX clock output port
 *  \param p_txer             TX error port
 *  \param p_txen             TX enable port
 *  \param p_txd              TX data port
 *
 *  \param rxclk              Clock used for receive timing
 *  \param rxclk_interframe   Clock used for interframe receive timing
 *  \param txclk              Clock used for transmit timing
 *  \param txclk_out          Second clock used for transmit timing
 *
 */
void rgmii_ethernet_mac(server ethernet_cfg_if i_cfg[n_cfg], static const unsigned n_cfg,
                        server ethernet_rx_if i_rx_lp[n_rx_lp], static const unsigned n_rx_lp,
                        server ethernet_tx_if i_tx_lp[n_tx_lp], static const unsigned n_tx_lp,
                        streaming chanend ? c_rx_hp,
                        streaming chanend ? c_tx_hp,
                        in port p_rxclk, in port p_rxer,
                        in port p_rxd_1000, in port p_rxd_10_100,
                        in port p_rxd_interframe,
                        in port p_rxdv, in port p_rxdv_interframe,
                        in port p_txclk_in, out port p_txclk_out,
                        out port p_txer, out port p_txen,
                        out port p_txd,
                        clock rxclk,
                        clock rxclk_interframe,
                        clock txclk,
                        clock txclk_out);

/** Ethernet component to connect to an MII interface (with real-time features).
 *
 *  This function implements an ethernet component connected to an
 *  MII interface with real-time features (prority queuing and traffic shaping).
 *  Interaction to the component is via the connected filtering, configuration
 *  and data interfaces.
 *
 *  \param i_cfg               Array of client configuration interfaces
 *  \param n_cfg               The number of configuration clients connected
 *
 *  \param i_rx_lp             Array of low priority receive clients
 *  \param n_rx_lp             The number of low priority receive clients connected
 *
 *  \param i_tx_lp             Array of low priority transmit clients
 *  \param n_tx_lp             The number of low priority transmit clients connected
 *
 *  \param c_rx_hp             Streaming channel end for high priority receive data
 *  \param c_tx_hp             Streaming channel end for high priority transmit data
 *
 *  \param n                   The number of clients connected
 *  \param p_rxclk             RX clock port
 *  \param p_rxer              RX error port
 *  \param p_rxd               RX data port
 *  \param p_rxdv              RX data valid port
 *  \param p_txclk             TX clock port
 *  \param p_txen              TX enable port
 *  \param p_txd               TX data port
 *  \param rxclk               Clock used for receive timing
 *  \param txclk               Clock used for transmit timing
 *  \param rx_bufsize_words    The number of words to used for a receive buffer.
 *                             This should be at least 500 words.
 *  \param tx_bufsize_words    The number of words to used for a transmit buffer.
 *                             This should be at least 500 words.
 *  \param rx_hp_bufsize_words The number of words to used for a high priority
 *                             receive buffer.
 *                             This should be at least 500 words.
 *  \param tx_hp_bufsize_words The number of words to used for a high priority
 *                             transmit buffer.
 *                             This should be at least 500 words.
 *  \param enable_shaper       This should be set to ``ETHERNET_ENABLE_SHAPER``
 *                             or ``ETHERNET_DISABLE_SHAPER`` to either enable
 *                             or disable the traffice shaper within the
 *                             MAC.
 */
void mii_ethernet_rt_mac(server ethernet_cfg_if i_cfg[n_cfg], static const unsigned n_cfg,
                         server ethernet_rx_if i_rx_lp[n_rx_lp], static const unsigned n_rx_lp,
                         server ethernet_tx_if i_tx_lp[n_tx_lp], static const unsigned n_tx_lp,
                         streaming chanend ? c_rx_hp,
                         streaming chanend ? c_tx_hp,
                         in port p_rxclk, in port p_rxer, in port p_rxd, in port p_rxdv,
                         in port p_txclk, out port p_txen, out port p_txd,
                         clock rxclk,
                         clock txclk,
                         static const unsigned rx_bufsize_words,
                         static const unsigned tx_bufsize_words,
                         enum ethernet_enable_shaper_t enable_shaper);

/** Ethernet component to connect to an MII interface.
 *
 *  This function implements an ethernet component connected to an
 *  MII interface.
 *  Interaction to the component is via the connected filtering, configuration
 *  and data interfaces.
 *
 *  \param i_cfg            Array of client configuration interfaces
 *  \param n_cfg            The number of configuration clients connected
 *
 *  \param i_rx             Array of receive clients
 *  \param n_rx             The number of receive clients connected
 *
 *  \param i_tx             Array of transmit clients
 *  \param n_tx             The number of transmit clients connected
 *
 *  \param n                The number of clients connected
 *  \param p_rxclk          RX clock port
 *  \param p_rxer           RX error port
 *  \param p_rxd            RX data port
 *  \param p_rxdv           RX data valid port
 *  \param p_txclk          TX clock port
 *  \param p_txen           TX enable port
 *  \param p_txd            TX data port
 *  \param p_timing         Internal timing port - this can be any xCORE port that
 *                          is not connected to any external device.
 *  \param rxclk            Clock used for receive timing
 *  \param txclk            Clock used for transmit timing
 *  \param rx_bufsize_words The number of words to used for a receive buffer.
                            This should be at least 1500 words.
 */
void mii_ethernet_mac(server ethernet_cfg_if i_cfg[n_cfg], static const unsigned n_cfg,
                      server ethernet_rx_if i_rx[n_rx], static const unsigned n_rx,
                      server ethernet_tx_if i_tx[n_tx], static const unsigned n_tx,
                      in port p_rxclk, in port p_rxer, in port p_rxd, in port p_rxdv,
                      in port p_txclk, out port p_txen, out port p_txd,
                      port p_timing,
                      clock rxclk,
                      clock txclk,
                      static const unsigned rx_bufsize_words);
#endif

#endif // __ethernet__h__
