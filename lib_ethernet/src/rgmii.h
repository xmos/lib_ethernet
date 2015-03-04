#ifndef _RGMII_H_
#define _RGMII_H_

typedef enum {
  INBAND_STATUS_1G_FULLDUPLEX = 0xd,
  INBAND_STATUS_100M_FULLDUPLEX = 0xb,
  INBAND_STATUS_10M_FULLDUPLEX = 0x9,
  INBAND_STATUS_OFF = 0x0
} rgmii_inband_status_t;

#ifdef __XC__
void log_speed_change_pointers(int speed_change_ids[4]);

void install_speed_change_handler(in buffered port:4 p_rxd_interframe, rgmii_inband_status_t current_mode);

void enable_rgmii(unsigned delay, unsigned divide);

void rgmii_rx_lld(streaming chanend c,
                  streaming chanend ping_pong,
                  int first,
                  streaming chanend c_speed_change,
                  in buffered port:32 p_rxd_1000,
                  in port p_rxdv,
                  in buffered port:1 p_rxer);

void rgmii_tx_lld(streaming chanend c,
                  out buffered port:32 p_txd,
                  streaming chanend c_speed_change);

#endif

#endif
