#ifndef __ethernet__h__
#define __ethernet__h__
#include <xs1.h>
#include <stdint.h>
#include <stddef.h>

/** Type representing the type of packet from the MAC */
typedef enum eth_packet_type_t {
  ETH_DATA,                      /**< A packet containing data. */
  ETH_IF_STATUS,                 /**< A control packet containing interface status information */
  ETH_OUTGOING_TIMESTAMP_INFO,   /**< A control packet containing an outgoing timestamp */
  ETH_NO_DATA                    /**< A packet containing no data. */
} eth_packet_type_t;

#define ETHERNET_ALL_INTERFACES  (-1)

#ifndef ETHERNET_MAX_PACKET_SIZE
#define ETHERNET_MAX_PACKET_SIZE (1518)
#endif

/** Type representing link events. */
typedef enum ethernet_link_state_t {
  ETHERNET_LINK_DOWN,    /**< Ethernet link down event. */
  ETHERNET_LINK_UP       /**< Ethernet link up event. */
} ethernet_link_state_t;

typedef struct ethernet_packet_info_t {
  eth_packet_type_t type;
  int len;
  unsigned timestamp;
  unsigned src_ifnum;
  unsigned filter_data;
} ethernet_packet_info_t;

#ifdef __XC__

typedef struct ethernet_macaddr_filter_t {
  uint16_t vlan;
  unsigned char addr[6];
  unsigned appdata;
} ethernet_macaddr_filter_t;

typedef enum ethernet_macaddr_filter_result_t {
  ETHERNET_MACADDR_FILTER_SUCCESS,
  ETHERNET_MACADDR_FILTER_TABLE_FULL
} ethernet_macaddr_filter_result_t;

/** Ethernet endpoint interface.
 *
 *  This interface allows clients to send and receive packets. */
typedef interface ethernet_if {
  void set_macaddr(size_t ifnum, unsigned char mac_address[6]);

  void get_macaddr(size_t ifnum, unsigned char mac_address[6]);

  ethernet_macaddr_filter_result_t
  add_macaddr_filter(ethernet_macaddr_filter_t entry);

  void del_macaddr_filter(ethernet_macaddr_filter_t entry);

  void del_all_macaddr_filters(void);

  void add_ethertype_filter(uint16_t ethertype);
  void del_ethertype_filter(uint16_t ethertype);

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

  void _init_send_packet(size_t n, int is_high_priority, size_t ifnum);
  void _complete_send_packet(char packet[n], unsigned n,
                             int request_timestamp, size_t ifnum);

  unsigned _get_outgoing_timestamp();

  [[notification]] slave void packet_ready();
  [[clears_notification]] void get_packet(ethernet_packet_info_t &desc,
                                          char data[n],
                                          unsigned n);
} ethernet_if;

extends client interface ethernet_if : {

  inline void send_packet(client ethernet_if i, char packet[n], unsigned n,
                          unsigned dst_port) {
    unsigned short etype = ((unsigned short) packet[12] << 8) + packet[13];
    int is_high_priority = (etype == 0x8100);
    i._init_send_packet(n, is_high_priority, dst_port);
    i._complete_send_packet(packet, n, 0, dst_port);
  }

  inline unsigned send_timed_packet(client ethernet_if i, char packet[n],
                                    unsigned n,
                                    unsigned dst_port) {
    unsigned short etype = ((unsigned short) packet[12] << 8) + packet[13];
    int is_high_priority = (etype == 0x8100);
    i._init_send_packet(n, is_high_priority, dst_port);
    i._complete_send_packet(packet, n, 1, dst_port);
    return i._get_outgoing_timestamp();
  }


}

enum ethernet_enable_shaper_t {
  ETHERNET_ENABLE_SHAPER,
  ETHERNET_DISABLE_SHAPER
};

/** Ethernet component to connect to an MII interface (with real-time features).
 *
 *  This function implements an ethernet component connected to an
 *  MII interface with real-time features (prority queuing and traffic shaping).
 *  Interaction to the component is via the connected filtering, configuration
 *  and data interfaces.
 *
 *  \param i_eth        array of interfaces to connect to the clients of the
 *                      MAC (i.e. the tasks sending/receiving data)
 *  \param n            the number of clients connected
 *  \param mac_address  The Ethernet MAC address for the component to use
 *  \param p_rxclk      RX clock port
 *  \param p_rxer       RX error port
 *  \param p_rxd        RX data port
 *  \param p_rxdv       RX data valid port
 *  \param p_txclk      TX clock port
 *  \param p_txen       TX enable port
 *  \param p_txd        TX data port
 *  \param rxclk        Clock used for receive timing
 *  \param txclk        Clock used for transmit timing
 *  \param rx_bufsize_words The number of words to used for a receive buffer.
 *                          This should be at least 500 words.
 *  \param tx_bufsize_words The number of words to used for a transmit buffer.
 *                          This should be at least 500 words.
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
void mii_ethernet_rt(server ethernet_if i_eth[n], static const unsigned n,
                     in port p_rxclk, in port p_rxer,
                     in port p_rxd, in port p_rxdv,
                     in port p_txclk, out port p_txen, out port p_txd,
                     clock rxclk,
                     clock txclk,
                     static const unsigned rx_bufsize_words,
                     static const unsigned tx_bufsize_words,
                     static const unsigned rx_hp_bufsize_words,
                     static const unsigned tx_hp_bufsize_words,
                     enum ethernet_enable_shaper_t enable_shaper);

/** Ethernet component to connect to an MII interface.
 *
 *  This function implements an ethernet component connected to an
 *  MII interface.
 *  Interaction to the component is via the connected filtering, configuration
 *  and data interfaces.
 *
 *  \param i_eth        array of interfaces to connect to the clients of the
 *                      MAC (i.e. the tasks sending/receiving data)
 *  \param n            the number of clients connected
 *  \param mac_address  The Ethernet MAC address for the component to use
 *  \param p_rxclk      RX clock port
 *  \param p_rxer       RX error port
 *  \param p_rxd        RX data port
 *  \param p_rxdv       RX data valid port
 *  \param p_txclk      TX clock port
 *  \param p_txen       TX enable port
 *  \param p_txd        TX data port
 *  \param p_timing     Internal timing port - this can be any xCORE port that
 *                      is not connected to any external device.
 *  \param rxclk        Clock used for receive timing
 *  \param txclk        Clock used for transmit timing
 *  \param rx_bufsize_words The number of words to used for a receive buffer.
                            This should be at least 1500 words.
 */
void mii_ethernet(server ethernet_if i_eth[n],
                  static const unsigned n,
                  in port p_rxclk, in port p_rxer, in port p_rxd, in port p_rxdv,
                  in port p_txclk, out port p_txen, out port p_txd,
                  port p_timing,
                  clock rxclk,
                  clock txclk,
                  static const unsigned rx_bufsize_words);
#endif

#endif // __ethernet__h__
