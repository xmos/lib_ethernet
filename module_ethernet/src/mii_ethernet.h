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

void mii_ethernet_server(client ethernet_filter_if i_filter,
                         server ethernet_config_if i_config,
                         server ethernet_if i_eth[n], static const unsigned n,
                         const char ?mac_address0[6],
                         otp_ports_t &?otp_ports,
                         mii_ports_t &mii_ports);

#endif

#endif //__mii_ethernet_h__

