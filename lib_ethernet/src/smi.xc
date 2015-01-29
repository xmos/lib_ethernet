// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <xs1.h>
#include "smi.h"
#include "print.h"



// SMI Registers
#define BASIC_CONTROL_REG                  0
#define BASIC_STATUS_REG                   1
#define PHY_ID1_REG                        2
#define PHY_ID2_REG                        3
#define AUTONEG_ADVERT_REG                 4
#define AUTONEG_LINK_REG                   5
#define AUTONEG_EXP_REG                    6

#define BASIC_CONTROL_LOOPBACK_BIT        14
#define BASIC_CONTROL_100_MBPS_BIT        13
#define BASIC_CONTROL_AUTONEG_EN_BIT      12
#define BASIC_CONTROL_RESTART_AUTONEG_BIT  9
#define BASIC_CONTROL_FULL_DUPLEX_BIT      8

#define BASIC_STATUS_LINK_BIT              2

#define AUTONEG_ADVERT_100_BIT             8
#define AUTONEG_ADVERT_10_BIT              6


// Clock is 4 times this rate.
#define SMI_CLOCK_DIVIDER   (100 / 10)


// Constants used in calls to smi_bit_shift and smi_reg.

#define SMI_READ 1
#define SMI_WRITE 0

#ifndef SMI_MDIO_RESET_MUX
#define SMI_MDIO_RESET_MUX 0
#endif

#ifndef SMI_MDIO_REST
#define SMI_MDIO_REST 0
#endif


// Shift in a number of data bits to or from the SMI port
static int smi_bit_shift(port p_smi_mdc, port ?p_smi_mdio,
                         unsigned data,
                         unsigned count, unsigned inning,
                         unsigned SMI_MDIO_BIT,
                         unsigned SMI_MDC_BIT)
{
    int i = count, data_bit = 0, t;

    if (isnull(p_smi_mdio)) {
        p_smi_mdc :> void @ t;
        if (inning) {
            while (i != 0) {
                i--;
                p_smi_mdc @ (t + 30) :> data_bit;
                data_bit &= (1 << SMI_MDIO_BIT);
                if (SMI_MDIO_RESET_MUX)
                  data_bit |= SMI_MDIO_REST;
                p_smi_mdc            <: data_bit;
                data = (data << 1) | (data_bit >> SMI_MDIO_BIT);
                p_smi_mdc @ (t + 60) <: 1 << SMI_MDC_BIT | data_bit;
                p_smi_mdc            :> void;
                t += 60;
            }
            p_smi_mdc @ (t+30) :> void;
        } else {
          while (i != 0) {
                i--;
                data_bit = ((data >> i) & 1) << SMI_MDIO_BIT;
                if (SMI_MDIO_RESET_MUX)
                  data_bit |= SMI_MDIO_REST;
                p_smi_mdc @ (t + 30) <:                    data_bit;
                p_smi_mdc @ (t + 60) <: 1 << SMI_MDC_BIT | data_bit;
                t += 60;
            }
            p_smi_mdc @ (t+30) <: 1 << SMI_MDC_BIT | data_bit;
        }
        return data;
    }
    else {
      p_smi_mdc <: ~0 @ t;
      while (i != 0) {
        i--;
        p_smi_mdc @ (t+30) <: 0;
        if (!inning) {
          int data_bit;
          data_bit = ((data >> i) & 1) << SMI_MDIO_BIT;
          if (SMI_MDIO_RESET_MUX)
            data_bit |= SMI_MDIO_REST;
          p_smi_mdio <: data_bit;
        }
        p_smi_mdc @ (t+60) <: ~0;
        if (inning) {
          p_smi_mdio :> data_bit;
          data_bit = data_bit >> SMI_MDIO_BIT;
          data = (data << 1) | data_bit;
        }
        t += 60;
      }
      p_smi_mdc @ (t+30) <: ~0;
      return data;
    }
}


[[distributable]]
void smi(server interface smi_if i, unsigned phy_address,
         port p_smi_mdio, port p_smi_mdc)
{
  if (SMI_MDIO_RESET_MUX) {
    timer tmr;
    int t;
    p_smi_mdio <: 0x0;
    tmr :> t;tmr when timerafter(t+100000) :> void;
    p_smi_mdio <: SMI_MDIO_REST;
  }

  p_smi_mdc <: 1;

  while (1) {
    select {
    case i.read_reg(uint8_t reg) -> uint16_t res:
      int inning = 1;
      int val;
      // Register access: lots of 1111, then a code (read/write), phy address,
      // register, and a turn-around, then data.
      smi_bit_shift(p_smi_mdc, p_smi_mdio, 0xffffffff, 32, SMI_WRITE,
                    0, 0);         // Preamble
      smi_bit_shift(p_smi_mdc, p_smi_mdio, (5+inning) << 10 | phy_address << 5 | reg,
                    14, SMI_WRITE,
                    0, 0);
      smi_bit_shift(p_smi_mdc, p_smi_mdio, 2, 2, inning,
                    0, 0);
      res = smi_bit_shift(p_smi_mdc, p_smi_mdio, val, 16, inning, 0, 0);
      break;
    case i.write_reg(uint8_t reg, uint16_t val):
      int inning = 0;
      // Register access: lots of 1111, then a code (read/write), phy address,
      // register, and a turn-around, then data.
      smi_bit_shift(p_smi_mdc, p_smi_mdio, 0xffffffff, 32, SMI_WRITE,
                    0, 0);         // Preamble
      smi_bit_shift(p_smi_mdc, p_smi_mdio, (5+inning) << 10 | phy_address << 5 | reg,
                    14, SMI_WRITE,
                    0, 0);
      smi_bit_shift(p_smi_mdc, p_smi_mdio, 2, 2, inning,
                    0, 0);
      (void) smi_bit_shift(p_smi_mdc, p_smi_mdio, val, 16, inning, 0, 0);
      break;
    }
  }
}

[[distributable]]
void smi_singleport(server interface smi_if i, unsigned phy_address,
                    port p_smi, unsigned SMI_MDIO_BIT, unsigned SMI_MDC_BIT)
{
  if (SMI_MDIO_RESET_MUX) {
    timer tmr;
    int t;
    p_smi <: 0x0;
    tmr :> t;tmr when timerafter(t+100000) :> void;
    p_smi <: SMI_MDIO_REST;
  }

  p_smi <: 1 << SMI_MDC_BIT;

  while (1) {
    select {
    case i.read_reg(uint8_t reg) -> uint16_t res:
      int inning = 1;
      int val;
      // Register access: lots of 1111, then a code (read/write), phy address,
      // register, and a turn-around, then data.
      smi_bit_shift(p_smi, null, 0xffffffff, 32, SMI_WRITE,
                    SMI_MDIO_BIT, SMI_MDC_BIT);         // Preamble
      smi_bit_shift(p_smi, null, (5+inning) << 10 | phy_address << 5 | reg,
                    14, SMI_WRITE,
                    SMI_MDIO_BIT, SMI_MDC_BIT);
      smi_bit_shift(p_smi, null, 2, 2, inning,
                    SMI_MDIO_BIT, SMI_MDC_BIT);
      res = smi_bit_shift(p_smi, null, val, 16, inning, SMI_MDIO_BIT, SMI_MDC_BIT);
      break;
    case i.write_reg(uint8_t reg, uint16_t val):
      int inning = 0;
      // Register access: lots of 1111, then a code (read/write), phy address,
      // register, and a turn-around, then data.
      smi_bit_shift(p_smi, null, 0xffffffff, 32, SMI_WRITE,
                    SMI_MDIO_BIT, SMI_MDC_BIT);         // Preamble
      smi_bit_shift(p_smi, null, (5+inning) << 10 | phy_address << 5 | reg,
                    14, SMI_WRITE,
                    SMI_MDIO_BIT, SMI_MDC_BIT);
      smi_bit_shift(p_smi, null, 2, 2, inning,
                    SMI_MDIO_BIT, SMI_MDC_BIT);
      (void) smi_bit_shift(p_smi, null, val, 16, inning, SMI_MDIO_BIT, SMI_MDC_BIT);
      break;
    }
  }
}



unsigned smi_get_id(client smi_if smi) {
  unsigned lo = smi.read_reg(PHY_ID1_REG);
  unsigned hi = smi.read_reg(PHY_ID2_REG);
  return ((hi >> 10) << 16) | lo;
}

void smi_configure(client smi_if smi, int is_eth_100, int is_auto)
{
  if (is_auto) {
    int auto_neg_advert_reg;
    auto_neg_advert_reg = smi.read_reg(AUTONEG_ADVERT_REG);

    // Clear bits [9:5]
    auto_neg_advert_reg &= 0xfc1f;

    // Set 100 or 10 Mpbs bits
    if (is_eth_100) {
      auto_neg_advert_reg |= 1 << AUTONEG_ADVERT_100_BIT;
    } else {
      auto_neg_advert_reg |= 1 << AUTONEG_ADVERT_10_BIT;
    }

    // Write back
    smi.write_reg(AUTONEG_ADVERT_REG, auto_neg_advert_reg);
  }

  int basic_control = smi.read_reg(BASIC_CONTROL_REG);
  if (is_auto) {
    // set autoneg bit
    basic_control |= 1 << BASIC_CONTROL_AUTONEG_EN_BIT;
    smi.write_reg(BASIC_CONTROL_REG, basic_control);
    // restart autoneg
    basic_control |= 1 << BASIC_CONTROL_RESTART_AUTONEG_BIT;
  }
  else {
    // set duplex mode, clear autoneg and 100 Mbps.
    basic_control |= 1 << BASIC_CONTROL_FULL_DUPLEX_BIT;
    basic_control &= ~( (1 << BASIC_CONTROL_AUTONEG_EN_BIT)|
                       (1 << BASIC_CONTROL_100_MBPS_BIT));
    if (is_eth_100) {                // Optionally set 100 Mbps
      basic_control |= 1 << BASIC_CONTROL_100_MBPS_BIT;
    }
  }
  smi.write_reg(BASIC_CONTROL_REG, basic_control);
}

void smi_set_loopback_mode(client smi_if smi, int enable)
{
  int control_reg = smi.read_reg(BASIC_CONTROL_REG);

  // First clear both autoneg and loopback
  control_reg = control_reg & ~ ((1 << BASIC_CONTROL_AUTONEG_EN_BIT) |
                               (1 << BASIC_CONTROL_LOOPBACK_BIT));
  // Now selectively set one of them
  if (enable) {
    control_reg = control_reg | (1 << BASIC_CONTROL_LOOPBACK_BIT);
  } else {
    control_reg = control_reg | (1 << BASIC_CONTROL_AUTONEG_EN_BIT);
  }

  smi.write_reg(BASIC_CONTROL_REG, control_reg);
}


int smi_is_link_up(client smi_if smi) {
  int link_up = ((smi.read_reg(BASIC_STATUS_REG) >> BASIC_STATUS_LINK_BIT) & 1);
  return link_up;
}
