// Copyright 2013-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __ethernet__h__
#define __ethernet__h__
#include <xs1.h>
#include <stdint.h>
#include <stddef.h>
#include <xccompat.h>
#include "doxygen.h"    // Sphynx Documentation Workarounds


#define ETHERNET_ALL_INTERFACES     (-1)
#define ETHERNET_MAX_PACKET_SIZE    (1518) /**< MAX packet size in bytes including src, dst, ether/tags but NOT preamble or CRC*/

#define MACADDR_NUM_BYTES           (6) /**< Number of octets in MAC address */

#define MII_CREDIT_FRACTIONAL_BITS  (16) /** Fractional bits for Qav credit based shaper setting */


/** Type representing the type of packet from the MAC */
typedef enum eth_packet_type_t {
  ETH_DATA,                      /**< A packet containing data. */
  ETH_IF_STATUS,                 /**< A control packet containing interface status information */
  ETH_OUTGOING_TIMESTAMP_INFO,   /**< A control packet containing an outgoing timestamp */
  ETH_NO_DATA                    /**< A packet containing no data. */
} eth_packet_type_t;

/** Type representing the PHY link speed and duplex */
typedef enum ethernet_speed_t {
  LINK_10_MBPS_FULL_DUPLEX,   /**< 10 Mbps full duplex */
  LINK_100_MBPS_FULL_DUPLEX,  /**< 100 Mbps full duplex */
  LINK_1000_MBPS_FULL_DUPLEX, /**< 1000 Mbps full duplex */
  NUM_ETHERNET_SPEEDS         /**< Count of speeds in this enum */
} ethernet_speed_t;

/** Type representing link events. */
typedef enum ethernet_link_state_t {
  ETHERNET_LINK_DOWN,    /**< Ethernet link down event. */
  ETHERNET_LINK_UP       /**< Ethernet link up event. */
} ethernet_link_state_t;

typedef struct {
  ethernet_link_state_t state;
  ethernet_speed_t speed;
}ethernet_link_t;

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
  uint8_t addr[MACADDR_NUM_BYTES]; /**< Six-octet destination MAC address to filter to the client that registers it */
  unsigned appdata;                /**< An optional word of user data that is stored by the Ethernet MAC and
                                        returned to the client when a packet is received with the
                                        destination MAC address indicated by the ``addr`` field */
} ethernet_macaddr_filter_t;

/** Type representing the result of adding a filter entry to the Ethernet MAC */
typedef enum ethernet_macaddr_filter_result_t {
  ETHERNET_MACADDR_FILTER_SUCCESS,    /**< The filter entry was added succesfully */
  ETHERNET_MACADDR_FILTER_TABLE_FULL  /**< The filter entry was not added because the filter table is full */
} ethernet_macaddr_filter_result_t;

#if (defined(__XC__) || defined(__DOXYGEN__))

/** Ethernet MAC configuration interface.
 *
 *  This interface allows clients to configure the Ethernet MAC.  */
#ifdef __XC__
typedef interface ethernet_cfg_if {
#endif
  /**
   * \addtogroup ethernet_config_if
   * @{
   */

  /** Set the source MAC address of the Ethernet MAC
   *
   * \param ifnum       The index of the MAC interface to set
   * \param mac_address The six-octet MAC address to set
   * Warning: The mac address set through this function is not used anywhere in the Mac. The client is expected
   * to create the full packet including src and dest mac address for transmission.
   * For setting a mac address filter when receiving packets, use add_macaddr_filter
   */
  void set_macaddr(size_t ifnum, const uint8_t mac_address[MACADDR_NUM_BYTES]);

  /** Gets the source MAC address of the Ethernet MAC
   *
   * \param ifnum       The index of the MAC interface to get
   * \param mac_address The six-octet MAC address of this interface
   */
  void get_macaddr(size_t ifnum, uint8_t mac_address[MACADDR_NUM_BYTES]);

  /** Set the current link state.
   *
   *  This function sets the current link state and speed of the PHY to the MAC.
   *
   *  \param ifnum      The index of the MAC interface to set
   *  \param new_state  The new link state for the port.
   *  \param speed      The active link speed and duplex of the PHY.
   */
  void set_link_state(int ifnum, ethernet_link_state_t new_state, ethernet_speed_t speed);

  /** Get the current link state.
   *
   *  This function Gets the current link state and speed of the PHY to the MAC.
   *
   *  \param ifnum      The index of the MAC interface to ge the link state for
   *
   *  \returns Ethernet link state and speed
   */
  void get_link_state(int ifnum, REFERENCE_PARAM(unsigned, link_state), REFERENCE_PARAM(unsigned, link_speed));

  /** Add MAC addresses to the filter. Only packets with the specified MAC address will be
   *  forwarded to the client.
   *
   *  \param client_num   The index into the set of RX clients. Can be acquired by
   *                      calling the get_index() method.
   *  \param is_hp        Indicates whether the RX client is high priority. There is
   *                      only one high priority client, so client_num must be 0 when
   *                      is_hp is set.
   *                      High priority queueing is only available in the 10/100 Mb/s real-time
   *                      and 10/100/1000 Mb/s MACs.
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
   *                      High priority queueing is only available in the 10/100 Mb/s real-time
   *                      and 10/100/1000 Mb/s MACs.
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
   *                      High priority queueing is only available in the 10/100 Mb/s real-time
   *                      and 10/100/1000 Mb/s MACs.
   */
  void del_all_macaddr_filters(size_t client_num, int is_hp);

  /** Add an Ethertype to the filter. This filter is applied after the MAC address filter and only if
   *  it is successful. Only packets with the specified Ethertypes will be forwarded to the client. A
   *  maximum of 2 Ethertype filters can be applied per client.
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

  /** Get the tile ID that the Ethernet MAC is running on and the current timer value on that tile.
   *  This function is only available in the 10/100 Mb/s real-time and 10/100/1000 Mb/s MACs.
   *
   *  \param tile_id      The tile ID returned from the Ethernet MAC
   *  \param time_on_tile The current timer value from the Ethernet MAC
   */
  void get_tile_id_and_timer_value(REFERENCE_PARAM(unsigned, tile_id), REFERENCE_PARAM(unsigned, time_on_tile));

  /** Set the high-priority TX queue's credit based shaper idle slope value.
   *  See also set_egress_qav_idle_slope_bps() where the argument is bits per second.
   *  This function is only available in the 10/100 Mb/s real-time and 10/100/1000 Mb/s MACs.
   *
   *  \param ifnum   The index of the MAC interface to set the slope (always 0)
   *  \param slope   The slope value in bits per 100 MHz ref timer tick in MII_CREDIT_FRACTIONAL_BITS Q format.
   *
   *
   */
  void set_egress_qav_idle_slope(size_t ifnum, unsigned slope);

  /** Set the high-priority TX queue's credit based shaper idle slope in bits per second.
   *  This function is only available in the 10/100 Mb/s real-time and 10/100/1000 Mb/s MACs.
   *
   *  \param ifnum   The index of the MAC interface to set the slope (always 0)
   *  \param slope   The maximum number of bits per second to be set
   *
   *
   */
  void set_egress_qav_idle_slope_bps(size_t ifnum, unsigned bits_per_second);


  /** Sets the the high-priority TX queue's  Qav credit limit in units of frame size bytes
   *
   *  \param ifnum         The index of the MAC interface to set the slope (always 0)
   *  \param limit_bytes   The credit limit in units of payload size in bytes to set as a credit limit,
   *                       not including preamble, CRC and IFG. Set to 0 for no limit (default)
   *
   */
  void set_egress_qav_credit_limit(size_t ifnum, int payload_limit_bytes);

  /** Set the ingress latency to correct for the offset between the timestamp
   *  measurement plane relative to the reference plane. See 802.1AS 8.4.3.
   *
   *  This latency can change at different PHY speeds, thus requires a latency
   *  value to be set for each speed in the ``ethernet_speed_t`` enum.
   *
   *  All ingress timestamps received by the client will be corrected
   *  with the set value. The latency is initialized to 0 for all speeds.
   *
   *  This function is only available in the 10/100 Mb/s real-time and 10/100/1000 Mb/s MACs.
   *
   *  \param ifnum   The index of the MAC interface to set the latency
   *  \param speed   The speed to set the latency for
   *  \param value   The latency value in nanoseconds
   */
  void set_ingress_timestamp_latency(size_t ifnum, ethernet_speed_t speed, unsigned value);

  /** Set the egress latency to correct for the offset between the timestamp
   *  measurement plane relative to the reference plane. See 802.1AS 8.4.3.
   *
   *  This latency can change at different PHY speeds, thus requires a latency
   *  value to be set for each speed in the ``ethernet_speed_t`` enum.
   *
   *  All egress timestamps received by the client will be corrected
   *  with the set value. The latency is initialized to 0 for all speeds.
   *
   *  This function is only available in the 10/100 Mb/s real-time and 10/100/1000 Mb/s MACs.
   *
   *  \param ifnum   The index of the MAC interface to set the latency
   *  \param speed   The speed to set the latency for
   *  \param value   The latency value in nanoseconds
   */
  void set_egress_timestamp_latency(size_t ifnum, ethernet_speed_t speed, unsigned value);

  /** Enable stripping of any VLAN tags on packets delivered to this client.
   *  This feature is available on the real-time 100 Mbps Ethernet MAC only.
   *
   *  \param client_num   The index into the set of RX clients. Can be acquired by
   *                      calling the get_index() method.
   */
  void enable_strip_vlan_tag(size_t client_num);

  /** Disable stripping of any VLAN tags on packets delivered to this client.
   *  This feature is available on the real-time 100 Mbps Ethernet MAC only.
   *
   *  \param client_num   The index into the set of RX clients. Can be acquired by
   *                      calling the get_index() method.
   */
  void disable_strip_vlan_tag(size_t client_num);

  /** Enable notifications of link status changes. These will be sent over the RX
   *  interface using ETH_IF_STATUS packets.
   *
   *  \param client_num   The index into the set of RX clients. Can be acquired by
   *                      calling the get_index() method.
   */
  void enable_link_status_notification(size_t client_num);

  /** Disable notifications of link status changes.
   *
   *  \param client_num   The index into the set of RX clients. Can be acquired by
   *                      calling the get_index() method.
   */
  void disable_link_status_notification(size_t client_num);

  /** Exit ethernet MAC. Quits all of the associated sub tasks and frees memory.
   * Allows the resources previously used by the MAC to be re-used by other tasks.
   * Only supported on RMII real-time MACs. This command is ignored for
   * other ethernet MACs.
   *
   */
  void exit(void);

#ifdef __XC__
} ethernet_cfg_if;
#endif

/**@}*/ // END: addtogroup ethernet_config_if




/** Ethernet MAC data transmit interface
 *
 *  This interface allows clients to send packets to the Ethernet MAC for transmission */
 /**
 * \addtogroup ethernet_tx_if
 * @{
 */
#ifdef __XC__
typedef interface ethernet_tx_if {
#endif

  /** Internal API call. Do not use. */
  void _init_send_packet(size_t n, size_t ifnum);
  /** Internal API call. Do not use. */
  void _complete_send_packet(char packet[n], unsigned n,
                             int request_timestamp, size_t ifnum);
  /** Internal API call. Do not use. */
  unsigned _get_outgoing_timestamp();
#ifdef __XC__
} ethernet_tx_if;

extends client interface ethernet_tx_if : {
#endif
  /** Function to send an Ethernet packet on the specified interface.
   *
   *  The call will block until a transmit buffer is available and the packet
   *  has been copied to the Ethernet MAC.
   *
   *  \param packet       A byte-array containing the Ethernet packet to send.
   *                      Must include a valid Ethernet frame header.
   *  \param n            The number of bytes in the packet array to send
   *  \param ifnum        The index of the MAC interface to send the packet
   *                      Use the ``ETHERNET_ALL_INTERFACES`` define to send to all interfaces.
   */
  inline void send_packet(CLIENT_INTERFACE(ethernet_tx_if, i), char packet[n], unsigned n,
                          unsigned ifnum) {
    i._init_send_packet(n, ifnum);
    i._complete_send_packet(packet, n, 0, ifnum);
  }

  /** Function to send an Ethernet packet on the specified interface and return a timestamp
   *  when the packet was sent by the MAC.
   *
   *  The call will block until the packet has been sent and the egress timestamp retrieved.
   *
   *  \param packet       A byte-array containing the Ethernet packet to send.
   *                      Must include a valid Ethernet frame header.
   *  \param n            The number of bytes in the packet array to send
   *  \param ifnum        The index of the MAC interface to send the packet
   *                      Use the ``ETHERNET_ALL_INTERFACES`` define to send to all interfaces.
   *  \returns            A 32-bit timestamp off a 100 MHz reference clock that represents
   *                      the egress time. May be corrected for egress latency, see
   *                      set_egress_timestamp_latency() on the ``ethernet_cfg_if`` interface.
   */
  inline unsigned send_timed_packet(CLIENT_INTERFACE(ethernet_tx_if, i), char packet[n],
                                    unsigned n,
                                    unsigned ifnum) {
    i._init_send_packet(n, ifnum);
    i._complete_send_packet(packet, n, 1, ifnum);
    return i._get_outgoing_timestamp();
  }
/**@}*/ // END: addtogroup ethernet_tx_if
#ifdef __XC__
}


/** Ethernet MAC data receive interface.
 *
 *  This interface allows clients to receive packets from the Ethernet MAC. */
typedef interface ethernet_rx_if {
#endif
  /**
   * \addtogroup ethernet_rx_if
   * @{
   */

  /** Get the index of a given receiver client
   *
   */
  size_t get_index();

  /** Packet ready notification.
   *
   *  This notification will fire when a packet has been queued for this
   *  client and is ready to be received using get_packet().
   *
   *  The event can be selected upon e.g.:
    \verbatim
    select {
      case i_eth_rx.packet_ready():
        ... // Get and handle the packet
      break;
    }
    \endverbatim
   */
   XC_NOTIFICATION slave void packet_ready();

  /** Function to receive an Ethernet packet or status/control data from the MAC.
   *  Should be called after a packet_ready() notification.
   *
   *  \param desc       A descriptor containing metadata about the packet contents.
   *  \param packet     A byte-array containing the packet data.
   *  \param n          The number of bytes to receive. The ``data`` array must be
   *                    large enough to receive the number of bytes specified.
   */
  XC_CLEARS_NOTIFICATION void get_packet(REFERENCE_PARAM(ethernet_packet_info_t, desc),
                                          char packet[n],
                                          unsigned n);
#ifdef __XC__
} ethernet_rx_if;
#endif

/**@}*/ // END: addtogroup ethernet_rx_if


/** Function to receive a priority-queued packet over a high priority channel
 *  from the 10/100 Mb/s real-time MAC.
 *
 *  The packet can be split into two transactions due to internal buffering
 *  and therefore this function must be used to receive the packet.
 *
 *  \param c_rx_hp     A streaming channel end connected to the MAC.
 *  \param packet      A byte-array containing the packet data.
 *  \param packet_info A descriptor containing metadata about the packet contents.
 *
 */
#pragma select handler
inline void ethernet_receive_hp_packet(streaming_chanend_t c_rx_hp,
                                       char packet[],
                                       REFERENCE_PARAM(ethernet_packet_info_t, packet_info))
{
  sin_char_array(c_rx_hp, (char *)&packet_info, sizeof(packet_info));

  unsigned len1 = packet_info.len & 0xffff;
  sin_char_array(c_rx_hp, packet, len1);
  unsigned len2 = packet_info.len >> 16;
  if (len2) {
    sin_char_array(c_rx_hp, &packet[len1], len2);
  }
  packet_info.len = len1 + len2;
}

/** Function to send a priority-queued packet over a high priority channel
 *  from the 10/100 Mb/s real-time MAC.
 *
 *  \param c_tx_hp     A streaming channel end connected to the MAC.
 *  \param packet      A byte-array containing the Ethernet packet to send.
 *                     Must include a valid Ethernet frame header.
 *  \param n           The number of bytes in the packet array to send
 *  \param ifnum       The index of the MAC interface to send the packet
 *                     Use the ``ETHERNET_ALL_INTERFACES`` define to send to all interfaces.
 */
inline void ethernet_send_hp_packet(streaming_chanend_t c_tx_hp,
                                    char packet[n],
                                    unsigned n,
                                    unsigned ifnum)
{
  c_tx_hp <: n;
  sout_char_array(c_tx_hp, packet, n);
}

/** Enum representing a flag to enable or disable the 802.1Qav credit based traffic shaper
 *  on the egress MAC port.
 */
enum ethernet_enable_shaper_t {
  ETHERNET_DISABLE_SHAPER = 0, /**< Disable the credit based shaper */
  ETHERNET_ENABLE_SHAPER       /**< Enable the credit based shaper */
};

/** Structure representing the port and clock resources required by RGMII
 *
 *  A macro to initialize this structure is provided:
    \verbatim
    rgmii_ports_t rgmii_ports = on tile[1]: RGMII_PORTS_INITIALIZER;
    \endverbatim
*/
typedef struct rgmii_ports_t {
  in_port_t p_rxclk;                    /**< RX clock port */
  in_buffered_port_1_t p_rxer;          /**< RX error port */
  in_buffered_port_32_t p_rxd_1000;     /**< 1Gb RX data port */
  in_buffered_port_32_t p_rxd_10_100;   /**< 10/100Mb RX data port */
  in_buffered_port_4_t p_rxd_interframe;/**< Interframe RX data port */
  in_port_t p_rxdv;                     /**< RX data valid port */
  in_port_t p_rxdv_interframe;          /**< Interframe RX data valid port */
  in_port_t p_txclk_in;                 /**< TX clock input port */
  out_port_t p_txclk_out;               /**< TX clock output port */
  out_port_t p_txer;                    /**< TX error port */
  out_port_t p_txen;                    /**< TX enable port */
  out_buffered_port_32_t p_txd;         /**< TX data port */
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

/** 10/100/1000 Mb/s Ethernet MAC component to connect to an RGMII interface.
 *
 *  This function implements a 10/100/1000 Mb/s Ethernet MAC component, connected to an RGMII
 *  interface, with real-time features.
 *  Interaction to the component is via the connected configuration
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
 *  \param c_rgmii_cfg        A streaming channel end connected to rgmii_ethernet_mac_config()
 *  \param rgmii_ports        A rgmii_ports_t structure initialized with the RGMII_PORTS_INITIALIZER macro
 *  \param shaper_enabled     This should be set to ``ETHERNET_ENABLE_SHAPER``
 *                            or ``ETHERNET_DISABLE_SHAPER`` to either enable
 *                            or disable the 802.1Qav traffic shaper within the
 *                            MAC.
 */
void rgmii_ethernet_mac(SERVER_INTERFACE(ethernet_rx_if, i_rx_lp[n_rx_lp]), static_const_unsigned_t n_rx_lp,
                        SERVER_INTERFACE(ethernet_tx_if, i_tx_lp[n_tx_lp]), static_const_unsigned_t n_tx_lp,
                        nullable_streaming_chanend_t c_rx_hp,
                        nullable_streaming_chanend_t c_tx_hp,
                        streaming_chanend_t c_rgmii_cfg,
                        REFERENCE_PARAM(rgmii_ports_t, rgmii_ports),
                        enum ethernet_enable_shaper_t shaper_enabled);

/** RGMII Ethernet MAC configuration task
 *
 *  This function implements the server side of the `ethernet_cfg_if` interface and
 *  communicates internally with the RGMII Ethernet MAC via a streaming channel end.
 *
 *  The function can be combined with SMI from within the top level par.
 *
 *  \param i_cfg              Array of client configuration interfaces
 *  \param n                  The number of configuration clients connected
 *  \param c_rgmii_cfg        A streaming channel end connected to rgmii_ethernet_mac()
 */
XC_COMBINABLE
void rgmii_ethernet_mac_config(SERVER_INTERFACE(ethernet_cfg_if, i_cfg[n]),
                               unsigned n,
                               streaming_chanend_t c_rgmii_cfg);


/** 10/100 Mb/s real-time Ethernet MAC component to connect to an MII interface.
 *
 *  This function implements a 10/100 Mb/s Ethernet MAC component, connected to an
 *  MII interface, with real-time features (priority queuing and traffic shaping).
 *  Interaction to the component is via the connected configuration
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
 *  \param p_rxclk             MII RX clock port
 *  \param p_rxer              MII RX error port
 *  \param p_rxd               MII RX data port
 *  \param p_rxdv              MII RX data valid port
 *  \param p_txclk             MII TX clock port
 *  \param p_txen              MII TX enable port
 *  \param p_txd               MII TX data port
 *  \param rxclk               Clock used for MII receive timing
 *  \param txclk               Clock used for MII transmit timing
 *  \param rx_bufsize_words    The number of words to used for a receive buffer.
 *                             This should be at least 500 words.
 *  \param tx_bufsize_words    The number of words to used for a transmit buffer.
 *                             This should be at least 500 words.
 *  \param shaper_enabled      This should be set to ``ETHERNET_ENABLE_SHAPER``
 *                             or ``ETHERNET_DISABLE_SHAPER`` to either enable
 *                             or disable the 802.1Qav traffic shaper within the
 *                             MAC.
 */
void mii_ethernet_rt_mac(SERVER_INTERFACE(ethernet_cfg_if, i_cfg[n_cfg]), static_const_unsigned_t n_cfg,
                         SERVER_INTERFACE(ethernet_rx_if, i_rx_lp[n_rx_lp]), static_const_unsigned_t n_rx_lp,
                         SERVER_INTERFACE(ethernet_tx_if, i_tx_lp[n_tx_lp]), static_const_unsigned_t n_tx_lp,
                         nullable_streaming_chanend_t c_rx_hp,
                         nullable_streaming_chanend_t c_tx_hp,
                         in_port_t p_rxclk, in_port_t p_rxer, in_port_t p_rxd, in_port_t p_rxdv,
                         in_port_t p_txclk, out_port_t p_txen, out_port_t p_txd,
                         clock rxclk,
                         clock txclk,
                         static_const_unsigned_t rx_bufsize_words,
                         static_const_unsigned_t tx_bufsize_words,
                         enum ethernet_enable_shaper_t shaper_enabled);

/** 10/100 Mb/s Ethernet MAC component that connects to an MII interface.
 *
 *  This function implements a 10/100 Mb/s Ethernet MAC component connected to
 *  an MII interface.
 *  Interaction to the component is via the connected configuration
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
 *  \param p_rxclk          MII RX clock port
 *  \param p_rxer           MII RX error port
 *  \param p_rxd            MII RX data port
 *  \param p_rxdv           MII RX data valid port
 *  \param p_txclk          MII TX clock port
 *  \param p_txen           MII TX enable port
 *  \param p_txd            MII TX data port
 *  \param p_timing         Internal timing port - this can be any xCORE port that
 *                          is not connected to any external device.
 *  \param rxclk            Clock used for MII receive timing
 *  \param txclk            Clock used for MII transmit timing
 *  \param rx_bufsize_words The number of words to used for a receive buffer.
                            This should be at least 1500 words.
 */
void mii_ethernet_mac(SERVER_INTERFACE(ethernet_cfg_if, i_cfg[n_cfg]), static_const_unsigned_t n_cfg,
                      SERVER_INTERFACE(ethernet_rx_if, i_rx[n_rx]), static_const_unsigned_t n_rx,
                      SERVER_INTERFACE(ethernet_tx_if, i_tx[n_tx]), static_const_unsigned_t n_tx,
                      in_port_t p_rxclk, in_port_t p_rxer, in_port_t p_rxd, in_port_t p_rxdv,
                      in_port_t p_txclk, out_port_t p_txen, out_port_t p_txd,
                      port p_timing,
                      clock rxclk,
                      clock txclk,
                      static_const_unsigned_t rx_bufsize_words);



/** ENUM to determine which two bits of a four bit port are to be used as data lines
 *  in the case that a four bit port is specified for RMII. The other two pins of the four bit
 *  port cannot be used. For Rx the input values are ignored. For Tx, the unused pins are always driven low. */
typedef enum rmii_data_4b_pin_assignment_t{
    USE_LOWER_2B = 0,                      /**< Use bit 0 and bit 1 of the four bit port for data bits 0 and 1*/
    USE_UPPER_2B = 1                       /**< Use bit 2 and bit 3 of the four bit port for data bits 0 and 1*/
} rmii_data_4b_pin_assignment_t;



/** 10/100 Mb/s real-time Ethernet MAC component to connect to an RMII interface.
 *
 *  This function implements a 10/100 Mb/s Ethernet MAC component, connected to an
 *  RMII interface, with real-time features (priority queuing and traffic shaping).
 *  Interaction to the component is via the connected configuration
 *  and data interfaces.
 *  Each of the 2 bit data ports may be defined either as half of a 4 bit port
 *  (upper or lower 2 bits) or a pair of 1 bit ports.
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
 *  \param p_clk               RMII clock input port
 *  \param p_rxd_0             Port for data bit 0 (1 bit option) or entire port (4 bit option)
 *  \param p_rxd_1             Port for data bit 1 (1 bit option). Pass null if unused.
 *  \param rx_pin_map          Which pins to use in 4 bit case. USE_LOWER_2B or USE_HIGHER_2B. Ignored if 1 bit ports used.
 *  \param p_rxdv              RMII RX data valid port
 *  \param p_txen              RMII TX enable port
 *  \param p_txd_0             Port for data bit 0 (1 bit option) or entire port (4 bit option)
 *  \param p_txd_1             Port for data bit 1 (1 bit option). Pass null if unused.
 *  \param tx_pin_map          Which pins to use in 4 bit case. USE_LOWER_2B or USE_HIGHER_2B. Ignored if 1 bit ports used.
 *  \param rxclk               Clock used for RMII receive timing
 *  \param txclk               Clock used for RMII transmit timing
 *  \param rx_bufsize_words    The number of words to used for a receive buffer.
 *                             This should be at least 500 long words.
 *  \param tx_bufsize_words    The number of words to used for a transmit buffer.
 *                             This should be at least 500 long words.
 *  \param shaper_enabled      This should be set to ``ETHERNET_ENABLE_SHAPER``
 *                             or ``ETHERNET_DISABLE_SHAPER`` to either enable
 *                             or disable the 802.1Qav traffic shaper within the
 *                             MAC.
 */
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
                          enum ethernet_enable_shaper_t shaper_enabled);

#endif // __XC__ || __DOXYGEN__

#endif // __ethernet__h__
