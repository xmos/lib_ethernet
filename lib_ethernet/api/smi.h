// Copyright (c) 2014-2017, XMOS Ltd, All rights reserved
#ifndef _smi_h_
#define _smi_h_
#include <stdint.h>
#include "ethernet.h"

// SMI Registers
#define BASIC_CONTROL_REG                  0x0
#define BASIC_STATUS_REG                   0x1
#define PHY_ID1_REG                        0x2
#define PHY_ID2_REG                        0x3
#define AUTONEG_ADVERT_REG                 0x4
#define AUTONEG_LINK_REG                   0x5
#define AUTONEG_EXP_REG                    0x6
#define GIGE_CONTROL_REG                   0x9

#define BASIC_CONTROL_LOOPBACK_BIT        14
#define BASIC_CONTROL_100_MBPS_BIT        13
#define BASIC_CONTROL_1000_MBPS_BIT        6
#define BASIC_CONTROL_AUTONEG_EN_BIT      12
#define BASIC_CONTROL_POWER_DOWN_BIT      11
#define BASIC_CONTROL_RESTART_AUTONEG_BIT  9
#define BASIC_CONTROL_FULL_DUPLEX_BIT      8

#define BASIC_STATUS_LINK_BIT              2

#define AUTONEG_ADVERT_1000BASE_T_FULL_DUPLEX             9
#define AUTONEG_ADVERT_100BASE_TX_FULL_DUPLEX             8
#define AUTONEG_ADVERT_10BASE_TX_FULL_DUPLEX              6

/** Type representing PHY auto negotiation enable/disable flags */
typedef enum smi_autoneg_t {
  SMI_DISABLE_AUTONEG,      /**< Enable auto negotiation */
  SMI_ENABLE_AUTONEG        /**< Disable auto negotiation */
} smi_autoneg_t;

#ifdef __XC__

/** SMI register configuration interface.
 *
 *  This interface allows clients to read or write the PHY SMI registers  */
typedef interface smi_if {
  /** Read the specified SMI register in the PHY
   *
   * \param phy_address  The 5-bit SMI address of the PHY
   * \param reg_address  The 5-bit register address to read
   * \returns            The 16-bit data value read from the register
   */
  uint16_t read_reg(uint8_t phy_address, uint8_t reg_address);

  /** Write the specified SMI register in the PHY
   *
   * \param phy_address  The 5-bit SMI address of the PHY
   * \param reg_address  The 5-bit register address to write
   * \param val          The 16-bit data value to write to the register
   */
  void write_reg(uint8_t phy_address, uint8_t reg_address, uint16_t val);
} smi_if;

/** SMI component that connects to an Ethernet PHY or switch via MDIO
 *  on separate ports.
 *
 *  This function implements a SMI component that connects to an 
 *  Ethernet PHY/ switch via MDIO/MDC connected on separate ports.
 *  Interaction to the component is via the connected SMI interface.
 *
 *  \param i_smi    Client register read/write interface
 *  \param p_mdio   SMI MDIO port
 *  \param p_mdc    SMI MDC port
 */
[[distributable]]
void smi(server interface smi_if i_smi,
         port p_mdio, port p_mdc);

/** SMI component that connects to an Ethernet PHY or switch via MDIO
 *  on a shared multi-bit port.
 *
 *  This function implements a SMI component that connects to an 
 *  Ethernet PHY/ switch via MDIO/MDC connected on the same multi-bit port.
 *  Interaction to the component is via the connected SMI interface.
 *
 *  \param i_smi    Client register read/write interface
 *  \param p_smi    The multi-bit port with MDIO/MDC pins
 *  \param mdio_bit The MDIO bit position on the multi-bit port
 *  \param mdc_bit  The MDC bit position on the multi-bit port
 */
[[distributable]]
void smi_singleport(server interface smi_if i_smi,
                    port p_smi,
                    unsigned mdio_bit, unsigned mdc_bit);

/** Function to configure the PHY speed/duplex with or without auto negotiation.
 *  The smi_phy_is_powered_down() function should be called to check that the PHY
 *  is not powered down before calling this function.
 *
 *  \param smi          An interface connection to the SMI component
 *  \param phy_address  The 5-bit SMI address of the PHY
 *  \param speed_mbps   If auto negotiation is disabled, the specified speed will
 *                      be forced, otherwise the PHY will be configured to advertise
 *                      as capable of all full-duplex speeds up to and including the
 *                      specified speed.
 *  \param auto_neg     If set to ``SMI_ENABLE_AUTONEG`` auto negotiation is enabled,
 *                      otherwise disabled if set to ``SMI_DISABLE_AUTONEG``
 */
void smi_configure(client smi_if smi, uint8_t phy_address, ethernet_speed_t speed_mbps, smi_autoneg_t auto_neg);

/** Function to enable loopback mode with the Ethernet PHY.
 *
 *  \param smi          An interface connection to the SMI component
 *  \param phy_address  The 5-bit SMI address of the PHY
 *  \param enable       Loopback enable flag. If set to 1, loopback is enabled, otherwise 0 to
 *                      disable
 */
void smi_set_loopback_mode(client smi_if smi, uint8_t phy_address, int enable);

/** Function to retrieve the PHY manufacturer ID number.
 *
 *  \param smi          An interface connection to the SMI component
 *  \param phy_address  The 5-bit SMI address of the PHY
 *  \returns            The PHY manufacturer ID number
 */
unsigned smi_get_id(client smi_if smi, uint8_t phy_address);

/** Reset PHY by writing bit 15 of the Control register
 *
 *  \param smi          An interface connection to the SMI component
 *  \param phy_address  The 5-bit SMI address of the PHY
 */
void smi_phy_reset(client smi_if smi, uint8_t phy_address);

/** Function to retrieve the power down status of the PHY.
 *
 *  \param smi          An interface connection to the SMI component
 *  \param phy_address  The 5-bit SMI address of the PHY
 *  \returns            ``1`` if the PHY is powered down, ``0`` otherwise
 */
unsigned smi_phy_is_powered_down(client smi_if smi, uint8_t phy_address);

/** SMI MMD write
 *
 *  Some PHYs expose additional registers to basic SMI through MMD,
 *  MDIO Manageable Device, annex 22D.
 *
 *  There is a suggested set of MMD registers in clause 45, but vendors
 *  don't necessarily follow it. It's best to refer to your PHY datasheet.
 *
 *  \param smi          An interface connection to the SMI component
 *  \param phy_address  The 5-bit SMI address of the PHY
 *  \param mmd_dev      16-bit MMD device address
 *  \param mmd_reg      16-bit MMD register number
 *  \param value        16-bit value to write
 */
void smi_mmd_write(client smi_if smi, uint8_t phy_address,
                   uint16_t mmd_dev, uint16_t mmd_reg,
		   uint16_t value);

/** Function to retrieve the link up/down status.
 *
 *  \param smi          An interface connection to the SMI component
 *  \param phy_address  The 5-bit SMI address of the PHY
 *  \returns            ``ETHERNET_LINK_UP`` if the link is up, ``ETHERNET_LINK_DOWN``
 *                      if the link is down
 */
ethernet_link_state_t smi_get_link_state(client smi_if smi, uint8_t phy_address);

#endif

#endif // _smi_h_
