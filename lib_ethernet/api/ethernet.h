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

/** Type representing the PHY link speed and duplex */
typedef enum ethernet_speed_t {
  LINK_10_MBPS_FULL_DUPLEX,   /**< 10 Mbps full duplex */
  LINK_100_MBPS_FULL_DUPLEX,  /**< 100 Mbps full duplex */
  LINK_1000_MBPS_FULL_DUPLEX, /**< 1000 Mbps full duplex */
  NUM_ETHERNET_SPEEDS
} ethernet_speed_t;

/** Type representing link events. */
typedef enum ethernet_link_state_t {
  ETHERNET_LINK_DOWN,    /**< Ethernet link down event. */
  ETHERNET_LINK_UP       /**< Ethernet link up event. */
} ethernet_link_state_t;

/** Structure representing a received data or control packet from the Ethernet MAC */
typedef struct ethernet_packet_info_t {
  eth_packet_type_t type; /**< Type representing the type of packet from the MAC */
  unsigned len;           /**< Length of the received packet in bytes */
  unsigned timestamp;     /**< The local time the packet was received by the MAC */
  unsigned src_ifnum;     /**< The index of the MAC interface that received the packet */
  unsigned filter_data;   /**< A word of user data that was registered with the MAC address filter */
} ethernet_packet_info_t;

/** Structure representing MAC address filter data that is registered with the Ethernet MAC */
typedef struct ethernet_macaddr_filter_t {
  unsigned char addr[6]; /**< Six-octet destination MAC address to filter to the client that registers it */
  unsigned appdata;      /**< An optional word of user data that is stored by the Ethernet MAC and
                              returned to the client when a packet is received with the
                              destination MAC address indicated by the ``addr`` field */
} ethernet_macaddr_filter_t;

/** Type representing the result of adding a filter entry to the Ethernet MAC */
typedef enum ethernet_macaddr_filter_result_t {
  ETHERNET_MACADDR_FILTER_SUCCESS,    /**< The filter entry was added succesfully */
  ETHERNET_MACADDR_FILTER_TABLE_FULL  /**< The filter entry was not added because the filter table is full */
} ethernet_macaddr_filter_result_t;

#ifdef __XC__

/** Ethernet MAC configuration interface.
 *
 *  This interface allows clients to configure the Ethernet MAC  */
typedef interface ethernet_cfg_if {
  /** Set the source MAC address of the Ethernet MAC
   *
   * \param ifnum       The index of the MAC interface to set
   * \param mac_address The six-octet MAC address to set
   */
  void set_macaddr(size_t ifnum, uint8_t mac_address[6]);

  /** Gets the source MAC address of the Ethernet MAC
   *
   * \param ifnum       The index of the MAC interface to get
   * \param mac_address The six-octet MAC address of this interface
   */
  void get_macaddr(size_t ifnum, uint8_t mac_address[6]);

  /** Set the current link state.
   *
   *  This function sets the current link state of the interface component.
   *
   *  \param ifnum      The index of the MAC interface to set
   *  \param new_state  The new link state for the port.
   *  \param speed      The active link speed and duplex of the port.
   */
  void set_link_state(int ifnum, ethernet_link_state_t new_state, ethernet_speed_t speed);

  /** Add MAC addresses to the filter.
   *
   *  \param client_num   The index into the set of RX clients. Can be acquired by
   *                      calling the get_index() method.
   *  \param is_hp        Indicates whether the RX client is high priority. There is
   *                      only one high priority client, so client_num must be 0 when
   *                      is_hp is set.
   *  \param entry        The filter entry to add.
   *
   *  \returns            ETHERNET_MACADDR_FILTER_SUCCESS when the entry is added or
   *                      ETHERNET_MACADDR_FILTER_TABLE_FULL on failure.
   *
   */
  ethernet_macaddr_filter_result_t
    add_macaddr_filter(size_t client_num, int is_hp, ethernet_macaddr_filter_t entry);

  /** Delete MAC addresses from the filter.
   *
   *  \param client_num   The index into the set of RX clients. Can be acquired by
   *                      calling the get_index() method.
   *  \param is_hp        Indicates whether the RX client is high priority. There is
   *                      only one high priority client, so client_num must be 0 when
   *                      is_hp is set.
   *  \param entry        The filter entry to delete.
   */
  void del_macaddr_filter(size_t client_num, int is_hp, ethernet_macaddr_filter_t entry);

  /** Delete all MAC addresses from the filter registered for this client.
   *
   *  \param client_num   The index into the set of RX clients. Can be acquired by
   *                      calling the get_index() method.
   *  \param is_hp        Indicates whether the RX client is high priority. There is
   *                      only one high priority client, so client_num must be 0 when
   *                      is_hp is set.
   */
  void del_all_macaddr_filters(size_t client_num, int is_hp);

  /** Add an Ethertype to the filter
   *
   *  \param client_num   The index into the set of RX clients. Can be acquired by
   *                      calling the get_index() method.
   *  \param ethertype    A two-octet Ethertype value to filter.
   */
  void add_ethertype_filter(size_t client_num, uint16_t ethertype);

  /** Delete an Ethertype from the filter
   *
   *  \param client_num   The index into the set of RX clients. Can be acquired by
   *                      calling the get_index() method.
   *  \param ethertype    A two-octet Ethertype value to delete from filter.
   */
  void del_ethertype_filter(size_t client_num, uint16_t ethertype);

  /** Get the tile ID that the Ethernet MAC is running on and the current timer value on that tile
   *
   *  \param tile_id      The tile ID returned from the Ethernet MAC
   *  \param time_on_tile The current timer value from the Ethernet MAC
   */
  void get_tile_id_and_timer_value(unsigned &tile_id, unsigned &time_on_tile);

  /** Set the high-priority TX queue's credit based shaper idle slope
   *
   * \param ifnum   The index of the MAC interface to set the slope
   * \param slope   The slope value
   */
  void set_egress_qav_idle_slope(size_t ifnum, unsigned slope);

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
#pragma select handler
inline void ethernet_receive_hp_packet(streaming chanend c_rx_hp,
                                       char buf[],
                                       ethernet_packet_info_t &packet_info)
{
  sin_char_array(c_rx_hp, (char *)&packet_info, sizeof(packet_info));

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

inline void ethernet_send_hp_packet(streaming chanend c_tx_hp,
                                    char packet[n],
                                    unsigned n,
                                    unsigned dst_port)
{
  c_tx_hp <: n;
  sout_char_array(c_tx_hp, packet, n);
}

enum ethernet_enable_shaper_t {
  ETHERNET_ENABLE_SHAPER,
  ETHERNET_DISABLE_SHAPER
};

/** Structure representing the port and clock resources required by RGMII */
typedef struct rgmii_ports_t {
  in port p_rxclk;                      /**< RX clock port */
  in buffered port:1 p_rxer;            /**< RX error port */
  in buffered port:32 p_rxd_1000;       /**< 1Gb RX data port */
  in buffered port:32 p_rxd_10_100;     /**< 10/100Mb RX data port */
  in buffered port:4 p_rxd_interframe;  /**< Interframe RX data port */
  in port p_rxdv;                       /**< RX data valid port */
  in port p_rxdv_interframe;            /**< Interframe RX data valid port */
  in port p_txclk_in;                   /**< TX clock input port */
  out port p_txclk_out;                 /**< TX clock output port */
  out port p_txer;                      /**< TX error port */
  out port p_txen;                      /**< TX enable port */
  out buffered port:32 p_txd;           /**< TX data port */
  clock rxclk;                          /**< Clock used for receive timing */
  clock rxclk_interframe;               /**< Clock used for interframe receive timing */
  clock txclk;                          /**< Clock used for transmit timing */
  clock txclk_out;                      /**< Second clock used for transmit timing */
} rgmii_ports_t;

#define RGMII_PORTS_INITIALIZER { \
  XS1_PORT_1O, \
  XS1_PORT_1A, \
  XS1_PORT_8A, \
  XS1_PORT_4E, \
  XS1_PORT_4F, \
  XS1_PORT_1B, \
  XS1_PORT_1K, \
  XS1_PORT_1P, \
  XS1_PORT_1G, \
  XS1_PORT_1E, \
  XS1_PORT_1F, \
  XS1_PORT_8B, \
  XS1_CLKBLK_1, \
  XS1_CLKBLK_2, \
  XS1_CLKBLK_3, \
  XS1_CLKBLK_4 \
}

/** Ethernet component to connect to an RGMII interface
 *
 *  This function implements an ethernet component connected to an RGMII
 *  interface.
 *  Interaction to the component is via the connected filtering, configuration
 *  and data interfaces.
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
 *  \param rgmii_ports        A rgmii_ports_t structure initialized with the RGMII_PORTS_INITIALIZER macro
 *  \param shaper_enabled     This should be set to ``ETHERNET_ENABLE_SHAPER``
 *                            or ``ETHERNET_DISABLE_SHAPER`` to either enable
 *                            or disable the traffice shaper within the
 *                            MAC.
 *
 */
void rgmii_ethernet_mac(server ethernet_rx_if i_rx_lp[n_rx_lp], static const unsigned n_rx_lp,
                        server ethernet_tx_if i_tx_lp[n_tx_lp], static const unsigned n_tx_lp,
                        streaming chanend ? c_rx_hp,
                        streaming chanend ? c_tx_hp,
                        streaming chanend c_rgmii_cfg,
                        rgmii_ports_t &rgmii_ports,
                        enum ethernet_enable_shaper_t shaper_enabled);

/** RGMII Ethernet MAC configuation task
 *
 *  This function implements the server side of the ethernet_cfg_if interface and
 *  communicates internally with the RGMII Ethernet MAC via a streaming channel end
 *
 *  \param i_cfg              Array of client configuration interfaces
 *  \param n                  The number of configuration clients connected
 *  \param c_rgmii_server     A streaming channel end connected to rgmii_ethernet_mac()
 */
[[combinable]]
void rgmii_ethernet_mac_config(server ethernet_cfg_if i_cfg[n],
                               unsigned n,
                               streaming chanend c_rgmii_server);


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
 *  \param shaper_enabled      This should be set to ``ETHERNET_ENABLE_SHAPER``
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
                         enum ethernet_enable_shaper_t shaper_enabled);

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
