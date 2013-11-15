#ifndef __mii_ethernet_h__
#define __mii_ethernet_h__
#include <xs1.h>
#include "ethernet.h"
#include "mii_ethernet_conf.h"
#include "otp_board_info.h"

#ifdef __XC__

typedef struct mii_ports_t {
    clock clk_rx;               /**< MII RX Clock Block **/
    clock clk_tx;               /**< MII TX Clock Block **/

    in port p_rxclk;            /**< MII RX clock wire */
    in port p_rxer;             /**< MII RX error wire */
    in buffered port:32 p_rxd;  /**< MII RX data wire */
    in port p_rxdv;             /**< MII RX data valid wire */

    in port p_txclk;            /**< MII TX clock wire */
    out port p_txen;            /**< MII TX enable wire */
    out buffered port:32 p_txd; /**< MII TX data wire */
} mii_ports_t;

void mii_ethernet_server_(client ethernet_filter_if ETHERNET_FILTER_SPECIALIZATION i_filter,
                          server ethernet_config_if i_config,
                          server ethernet_if i_eth[n], static const unsigned n,
                          const char mac_address[6],
                          mii_ports_t &mii_ports,
                          static const unsigned rx_bufsize_words,
                          static const unsigned tx_bufsize_words,
                          static const unsigned rx_hp_bufsize_words,
                          static const unsigned tx_hp_bufsize_words,
                          int enable_shaper);

#define mii_ethernet_server(i_filter, i_config, i_eth, n, m_addr, mii, rx_bufsize, tx_bufsize, rx_hp_bufsize, tx_hp_bufsize, enable_shaper) mii_ethernet_server_(i_filter, i_config, i_eth, n, m_addr, mii, rx_bufsize/4, tx_bufsize/4, rx_hp_bufsize/4, tx_hp_bufsize/4, enable_shaper)


void mii_ethernet_lite_server_(client ethernet_filter_if i_filter,
                               server ethernet_config_if i_config,
                               server ethernet_if i_eth[n],
                               static const unsigned n,
                               const char mac_address[6],
                               mii_ports_t &mii_ports,
                               port p_timing,
                               static const unsigned double_rx_bufsize_words);

#define mii_ethernet_lite_server(i_filter, i_config, i_eth, n, m_addr, mii, p, rx_bufsize) mii_ethernet_lite_server_(i_filter, i_config, i_eth, n, m_addr, mii, p, (rx_bufsize/4)*2)

#endif

#endif //__mii_ethernet_h__

