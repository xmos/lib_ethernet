// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#ifndef _smi_h_
#define _smi_h_

#include <xs1.h>
#include <xccompat.h>
#include "ethernet.h"

#ifdef __smi_conf_h_exists__
#include "smi_conf.h"
#endif


#ifndef SMI_COMBINE_MDC_MDIO
#define SMI_COMBINE_MDC_MDIO 0
#endif

#ifdef __XC__

/** Structure containing resources required for the SMI ethernet phy interface.
 *
 * This structure can be filled in two ways. One indicate that the SMI
 * interface is connected using two 1-bit port, the other indicates that
 * the interface is connected using a single multi-bit port.
 *
 * If used with two 1-bit ports, set the ``phy_address``, ``p_smi_mdio``
 * and ``p_smi_mdc`` as normal.
 *
 * If SMI_COMBINE_MDC_MDIO is 1 then ``p_smi_mdio`` is ommited and ``p_mdc`` is
 * assumbed to multibit port containing both mdio and mdc.
 *
 */
typedef struct smi_ports_t {
    port ?p_smi_mdio;           /**< MDIO port. */
    port  p_smi_mdc;            /**< MDC port.  */
} smi_ports_t;

typedef interface smi_if {
  int readwrite_reg(unsigned reg, unsigned val, int inning);
} smi_if;

extends client interface smi_if : {

  inline int read_reg(client smi_if i, unsigned reg) {
    return i.readwrite_reg(reg, 0, 1);
  }

  inline void write_reg(client smi_if i, unsigned reg, unsigned value) {
    i.readwrite_reg(reg, value, 0);
  }

  /** Function that configures the Ethernet PHY.
   *
   *    Full duplex is always advertised
   *
   *   \param is_eth_100         If non-zero, 100BaseT is advertised
   *                             to the link peer
   *   \param is_auto_negotiate  If non-zero, the phy is set to auto negotiate
   */
  void configure_phy(client smi_if i, int is_eth_100, int is_auto_negotiate);

  /** Function that can enable or disable loopback in the phy.
   *
   * \param enable  set to 1 to enable loopback,
   *                or 0 to disable loopback.
   */
  void set_loopback_mode(client smi_if i, int enable);

  /** Function that returns the PHY identification.
   *
   * \returns the 32-bit identifier.
   */
  unsigned get_phy_id(client smi_if i);

  /** Function that polls whether the link is alive.
   *
   * \returns ethernet link state - either ETHERNET_LINK_UP or
   *          ETHERNET_LINK_DOWN
   */
  ethernet_link_state_t get_link_state(client smi_if i);
}

[[distributable]]
void smi(server smi_if i, unsigned phy_address, smi_ports_t &smi_ports);

#endif

#endif
