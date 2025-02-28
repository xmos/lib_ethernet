// Copyright 2011-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include "smi.h"
#include "print.h"
#include "xassert.h"

// Constants used in calls to smi_bit_shift and smi_reg.

#define SMI_READ                    1
#define SMI_WRITE                   0

#define MMD_ACCESS_CONTROL          0xD
#define MMD_ACCESS_DATA             0xE

// This is setup to support a tVAL time of 300ns (LAN8710A) for read
// using the single port version. If using the two port version you 
// may double this bit clock and still meet timing.
// Or if your PHY is faster than 300ns tVAL you may increase the BIT_CLOCK_HZ
#define SMI_BIT_CLOCK_HZ            1660000
#define SMI_BIT_TIME_TICKS          (XS1_TIMER_HZ / SMI_BIT_CLOCK_HZ)
#define SMI_HALF_BIT_TIME_TICKS     (SMI_BIT_TIME_TICKS / 2)

/* Notes about single port implementation.
Sampling just before the rising edge is the correct thing to do for maximum performance
(min cycle time) so we do that in the two port version.
In the single port version we have a challenge due to not having full control of direction 
on individual port bits:
The PHY will start driving data from the MDC rising edge so we must be high-Z on the data port
at that point (and clock gets pulled high externally).
We run slow enough so that the data presented on MDIO is valid by time of the falling edge, which is then sampled.
However we then need to drive the low clock to complete the cycle which we do actively.
We also drive back the read data so that it doesn't contend. This effectively doubles the
required cycle time but does work.
*/

// Shift in a number of data bits to or from the SMI port
static int smi_bit_shift(port p_smi_mdc, port ?p_smi_mdio,
                         unsigned write_data,
                         unsigned count, unsigned is_read,
                         unsigned SMI_MDIO_BIT,
                         unsigned SMI_MDC_BIT)
{
  timer t;
  int t_trigger;

  unsigned read_data = 0;

  // Single port version. Note this requires that MDC is pulled up externally.
  if (isnull(p_smi_mdio)) {
    // Start of MDC clock cycle
    // port Hi-Z. Clock will rise via pull-up, data is Hi-Z
    t :> t_trigger;
    p_smi_mdc :> void; 
    if (is_read) {
      while (count != 0) {
        count--;
        // Wait til half cycle
        t_trigger += SMI_HALF_BIT_TIME_TICKS;
        t when timerafter(t_trigger) :> void;

        // Read port with PHY driven data bit just before falling edge of clock
        unsigned port_data;
        p_smi_mdc :> port_data;
        port_data &= ~(1 << SMI_MDC_BIT);   // clear clock bit to zero
        // Assert clock low and drive back previously read data (to avoid contention) 
        p_smi_mdc <: port_data;             // drive back data and assert clock low    
        read_data |=  (port_data >> SMI_MDIO_BIT) << count;
 
        // Wait til end of cycle
        t_trigger += SMI_HALF_BIT_TIME_TICKS;
        t when timerafter(t_trigger) :> void;

        // At end of cycle allow clock to be pulled high, data is Hi-Z 
        p_smi_mdc :> void;
      }
    }
    else
    // Write
    {
      // port is hi-z so MDC is pulled high, data undriven
      while (count != 0) {
        count--;
        unsigned data_bit = ((write_data >> count) & 1) << SMI_MDIO_BIT;

        // Wait til half cycle
        t_trigger += SMI_HALF_BIT_TIME_TICKS;
        t when timerafter(t_trigger) :> void;
        // drive required data bit and MDC low halfway through
        p_smi_mdc <: data_bit;

        // Wait til end of cycle
        t_trigger += SMI_HALF_BIT_TIME_TICKS;
        t when timerafter(t_trigger) :> void;

        // Continue to drive data bit and clock high at end of cycle
        p_smi_mdc <: 1 << SMI_MDC_BIT | data_bit;
      }
    }

    return read_data;
  }
  else
  // Two port version
  {
    // Clock high
    t :> t_trigger;
    p_smi_mdc <: 1;
    while(count != 0){
      count--;

      // Wait til half cycle
      t_trigger += SMI_HALF_BIT_TIME_TICKS;
      t when timerafter(t_trigger) :> void;
      // Falling edge and data assert or hi-z
      if(is_read){
        p_smi_mdio :> void; // Hi-Z
      }
      else
      {
        unsigned data_bit = (write_data >> count) & 1;
        p_smi_mdio <: data_bit;
      }
      p_smi_mdc <: 0;

      // Wait til end of cycle
      t_trigger += SMI_HALF_BIT_TIME_TICKS;
      t when timerafter(t_trigger) :> void;
      if(is_read){
        unsigned data_bit;
        p_smi_mdio :> data_bit;
        read_data |= (data_bit << count);
      }
      else
      {
        // Keep previous data bit asserted
      }
      // Rising edge
      p_smi_mdc <: 1;
    } // count != 0

    return read_data;
  } // Two port
}


[[distributable]]
void smi(server interface smi_if i,
         port p_smi_mdio, port p_smi_mdc)
{

  p_smi_mdc <: 1;

  while (1) {
    select {
    case i.read_reg(uint8_t phy_addr, uint8_t reg_addr) -> uint16_t res:
      int is_read = 1;
      int val;
      // Register access: lots of 1111, then a code (read/write), phy address,
      // register, and a turn-around, then data.
      smi_bit_shift(p_smi_mdc, p_smi_mdio, 0xffffffff, 32, SMI_WRITE,
                    0, 0);         // Preamble
      smi_bit_shift(p_smi_mdc, p_smi_mdio, (5+is_read) << 10 | phy_addr << 5 | reg_addr,
                    14, SMI_WRITE,
                    0, 0);
      smi_bit_shift(p_smi_mdc, p_smi_mdio, 2, 2, is_read,
                    0, 0);
      res = smi_bit_shift(p_smi_mdc, p_smi_mdio, val, 16, is_read, 0, 0);

      // Ensure MDIO is pull high at end after 100ns at end of transaction
      delay_ticks(10);
      p_smi_mdio :> void;
      break;
    case i.write_reg(uint8_t phy_addr, uint8_t reg_addr, uint16_t val):
      int is_read = 0;
      // Register access: lots of 1111, then a code (read/write), phy address,
      // register, and a turn-around, then data.
      smi_bit_shift(p_smi_mdc, p_smi_mdio, 0xffffffff, 32, SMI_WRITE,
                    0, 0);         // Preamble
      smi_bit_shift(p_smi_mdc, p_smi_mdio, (5+is_read) << 10 | phy_addr << 5 | reg_addr,
                    14, SMI_WRITE,
                    0, 0);
      smi_bit_shift(p_smi_mdc, p_smi_mdio, 2, 2, is_read,
                    0, 0);
      (void) smi_bit_shift(p_smi_mdc, p_smi_mdio, val, 16, is_read, 0, 0);
      
      // Ensure MDIO is pull high at end after 100ns at end of transaction
      delay_ticks(10);
      p_smi_mdio :> void;
      break;
    }
  }
}

[[distributable]]
void smi_singleport(server interface smi_if i,
                    port p_smi, unsigned SMI_MDIO_BIT, unsigned SMI_MDC_BIT)
{

  p_smi <: 1 << SMI_MDC_BIT;

  while (1) {
    select {
    case i.read_reg(uint8_t phy_addr, uint8_t reg_addr) -> uint16_t res:
      int is_read = 1;
      int val;
      // Register access: lots of 1111, then a code (read/write), phy address,
      // register, and a turn-around, then data.
      smi_bit_shift(p_smi, null, 0xffffffff, 32, SMI_WRITE,
                    SMI_MDIO_BIT, SMI_MDC_BIT);         // Preamble
      smi_bit_shift(p_smi, null, (5+is_read) << 10 | phy_addr << 5 | reg_addr,
                    14, SMI_WRITE,
                    SMI_MDIO_BIT, SMI_MDC_BIT);
      smi_bit_shift(p_smi, null, 2, 2, is_read,
                    SMI_MDIO_BIT, SMI_MDC_BIT);
      res = smi_bit_shift(p_smi, null, val, 16, is_read, SMI_MDIO_BIT, SMI_MDC_BIT);

      // port already high so MDC and MDIO will be pulled high
      break;
    case i.write_reg(uint8_t phy_addr, uint8_t reg_addr, uint16_t val):
      int is_read = 0;
      // Register access: lots of 1111, then a code (read/write), phy address,
      // register, and a turn-around, then data.
      smi_bit_shift(p_smi, null, 0xffffffff, 32, SMI_WRITE,
                    SMI_MDIO_BIT, SMI_MDC_BIT);         // Preamble
      smi_bit_shift(p_smi, null, (5+is_read) << 10 | phy_addr << 5 | reg_addr,
                    14, SMI_WRITE,
                    SMI_MDIO_BIT, SMI_MDC_BIT);
      smi_bit_shift(p_smi, null, 2, 2, is_read,
                    SMI_MDIO_BIT, SMI_MDC_BIT);
      (void) smi_bit_shift(p_smi, null, val, 16, is_read, SMI_MDIO_BIT, SMI_MDC_BIT);

      // Ensure MDIO is pull high at end after 100ns at end of transaction
      delay_ticks(10);
      p_smi :> void;
      break;
    }
  }
}

unsigned smi_get_id(client smi_if smi, uint8_t phy_address) {
  unsigned lo = smi.read_reg(phy_address, PHY_ID1_REG);
  unsigned hi = smi.read_reg(phy_address, PHY_ID2_REG);
  return ((hi >> 10) << 16) | lo;
}

void smi_phy_reset(client smi_if smi, uint8_t phy_address)
{
  smi.write_reg(phy_address, BASIC_CONTROL_REG, 1 << 15);
  delay_microseconds(500);
  int control_reg;

  do {
    control_reg = smi.read_reg(phy_address, BASIC_CONTROL_REG);
  } while ((control_reg >> 15) & 1);
}

unsigned smi_phy_is_powered_down(client smi_if smi, uint8_t phy_address)
{
  return ((smi.read_reg(phy_address, BASIC_CONTROL_REG) >> BASIC_CONTROL_POWER_DOWN_BIT) & 1);
}

void smi_mmd_write(client smi_if smi, uint8_t phy_address,
                   uint16_t mmd_dev, uint16_t mmd_reg,
		   uint16_t value)
{
  smi.write_reg(phy_address, MMD_ACCESS_CONTROL, mmd_dev);
  smi.write_reg(phy_address, MMD_ACCESS_DATA, mmd_reg);
  smi.write_reg(phy_address, MMD_ACCESS_CONTROL, (1 << 14) | mmd_dev); 
  smi.write_reg(phy_address, MMD_ACCESS_DATA, value);
}

void smi_configure(client smi_if smi, uint8_t phy_address, ethernet_speed_t speed_mbps, smi_autoneg_t auto_neg)
{
  if (speed_mbps != LINK_10_MBPS_FULL_DUPLEX &&
      speed_mbps != LINK_100_MBPS_FULL_DUPLEX &&
      speed_mbps != LINK_1000_MBPS_FULL_DUPLEX) {
    fail("Invalid Ethernet speed provided, must be 10, 100 or 1000");
  }

  if (auto_neg == SMI_ENABLE_AUTONEG) {
    uint16_t auto_neg_advert_100_reg = smi.read_reg(phy_address, AUTONEG_ADVERT_REG);
    uint16_t gige_control_reg = smi.read_reg(phy_address, GIGE_CONTROL_REG);

    // Clear bits [9:5]
    auto_neg_advert_100_reg &= 0xfc1f;
    // Clear bits [9:8]
    gige_control_reg &= 0xfcff;

    switch (speed_mbps) {
    #pragma fallthrough
      case LINK_1000_MBPS_FULL_DUPLEX: gige_control_reg |= 1 << AUTONEG_ADVERT_1000BASE_T_FULL_DUPLEX;
    #pragma fallthrough
      case LINK_100_MBPS_FULL_DUPLEX: auto_neg_advert_100_reg |= 1 << AUTONEG_ADVERT_100BASE_TX_FULL_DUPLEX;
      case LINK_10_MBPS_FULL_DUPLEX: auto_neg_advert_100_reg |= 1 << AUTONEG_ADVERT_10BASE_TX_FULL_DUPLEX; break;
      default: __builtin_unreachable(); break;
    }

    // Write back
    smi.write_reg(phy_address, AUTONEG_ADVERT_REG, auto_neg_advert_100_reg);
    smi.write_reg(phy_address, GIGE_CONTROL_REG, gige_control_reg);
  }

  uint16_t basic_control = smi.read_reg(phy_address, BASIC_CONTROL_REG);
  if (auto_neg == SMI_ENABLE_AUTONEG) {
    // set autoneg bit
    basic_control |= 1 << BASIC_CONTROL_AUTONEG_EN_BIT;
    smi.write_reg(phy_address, BASIC_CONTROL_REG, basic_control);
    // restart autoneg
    basic_control |= 1 << BASIC_CONTROL_RESTART_AUTONEG_BIT;
  }
  else {
    // set duplex mode, clear autoneg and speed
    basic_control |= 1 << BASIC_CONTROL_FULL_DUPLEX_BIT;
    basic_control &= ~( (1 << BASIC_CONTROL_AUTONEG_EN_BIT)|
                          (1 << BASIC_CONTROL_100_MBPS_BIT)|
                         (1 << BASIC_CONTROL_1000_MBPS_BIT));

    if (speed_mbps == LINK_100_MBPS_FULL_DUPLEX) {
      basic_control |= 1 << BASIC_CONTROL_100_MBPS_BIT;
    } else if (speed_mbps == LINK_1000_MBPS_FULL_DUPLEX) {
      fail("Autonegotiation cannot be disabled in 1000 Mbps mode");
    }
  }
  smi.write_reg(phy_address, BASIC_CONTROL_REG, basic_control);
}

void smi_set_loopback_mode(client smi_if smi, uint8_t phy_address, int enable)
{
  uint16_t control_reg = smi.read_reg(phy_address, BASIC_CONTROL_REG);

  // First clear both autoneg and loopback
  control_reg = control_reg & ~ ((1 << BASIC_CONTROL_AUTONEG_EN_BIT) |
                               (1 << BASIC_CONTROL_LOOPBACK_BIT));
  // Now selectively set one of them
  if (enable) {
    control_reg = control_reg | (1 << BASIC_CONTROL_LOOPBACK_BIT);
  } else {
    control_reg = control_reg | (1 << BASIC_CONTROL_AUTONEG_EN_BIT);
  }

  smi.write_reg(phy_address, BASIC_CONTROL_REG, control_reg);
}

ethernet_link_state_t smi_get_link_state(client smi_if smi, uint8_t phy_address) {
  unsigned link_up = ((smi.read_reg(phy_address, BASIC_STATUS_REG) >> BASIC_STATUS_LINK_BIT) & 1);
  return link_up ? ETHERNET_LINK_UP : ETHERNET_LINK_DOWN;;
}
