// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <xs1.h>

#include "smi.h"
#include "print.h"

#ifndef ETHERNET_PHY_RESET_TIMER_TICKS
#define ETHERNET_PHY_RESET_TIMER_TICKS 100
#endif

#ifndef SMI_MDIO_RESET_MUX
#define SMI_MDIO_RESET_MUX 0
#endif

#ifndef SMI_MDIO_REST
#define SMI_MDIO_REST 0
#endif

#ifndef SMI_HANDLE_COMBINED_PORTS
  #if SMI_COMBINE_MDC_MDIO
     #define SMI_HANDLE_COMBINED_PORTS 1
  #else
     #define SMI_HANDLE_COMBINED_PORTS 0
  #endif
#endif

#if SMI_HANDLE_COMBINED_PORTS
  #ifndef SMI_MDC_BIT
  #warning SMI_MDC_BIT not defined in smi_conf.h - Assuming 0
  #define SMI_MDC_BIT 0
  #endif

  #ifndef SMI_MDIO_BIT
  #warning SMI_MDIO_BIT not defined in smi_conf.h - Assuming 1
  #define SMI_MDIO_BIT 1
  #endif
#else
  #ifndef SMI_MDIO_BIT
  #define SMI_MDIO_BIT 0
  #endif
  #ifndef SMI_MDC_BIT
  #define SMI_MDC_BIT 0
  #endif
#endif

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

// Shift in a number of data bits to or from the SMI port
static int smi_bit_shift(smi_ports_t &smi, unsigned data, unsigned count, unsigned inning) {
    int i = count, dataBit = 0, t;

    if (SMI_HANDLE_COMBINED_PORTS && isnull(smi.p_smi_mdio)) {
        smi.p_smi_mdc :> void @ t;
        if (inning) {
            while (i != 0) {
                i--;
                smi.p_smi_mdc @ (t + 30) :> dataBit;
                dataBit &= (1 << SMI_MDIO_BIT);
                if (SMI_MDIO_RESET_MUX)
                  dataBit |= SMI_MDIO_REST;
                smi.p_smi_mdc            <: dataBit;
                data = (data << 1) | (dataBit >> SMI_MDIO_BIT);
                smi.p_smi_mdc @ (t + 60) <: 1 << SMI_MDC_BIT | dataBit;
                smi.p_smi_mdc            :> void;
                t += 60;
            }
            smi.p_smi_mdc @ (t+30) :> void;
        } else {
          while (i != 0) {
                i--;
                dataBit = ((data >> i) & 1) << SMI_MDIO_BIT;
                if (SMI_MDIO_RESET_MUX)
                  dataBit |= SMI_MDIO_REST;
                smi.p_smi_mdc @ (t + 30) <:                    dataBit;
                smi.p_smi_mdc @ (t + 60) <: 1 << SMI_MDC_BIT | dataBit;
                t += 60;
            }
            smi.p_smi_mdc @ (t+30) <: 1 << SMI_MDC_BIT | dataBit;
        }
        return data;
    }
    else {
      smi.p_smi_mdc <: ~0 @ t;
      while (i != 0) {
        i--;
        smi.p_smi_mdc @ (t+30) <: 0;
        if (!inning) {
          int dataBit;
          dataBit = ((data >> i) & 1) << SMI_MDIO_BIT;
          if (SMI_MDIO_RESET_MUX)
            dataBit |= SMI_MDIO_REST;
          smi.p_smi_mdio <: dataBit;
        }
        smi.p_smi_mdc @ (t+60) <: ~0;
        if (inning) {
          smi.p_smi_mdio :> dataBit;
          dataBit = dataBit >> SMI_MDIO_BIT;
          data = (data << 1) | dataBit;
        }
        t += 60;
      }
      smi.p_smi_mdc @ (t+30) <: ~0;
      return data;
    }
}

[[distributable]]
void smi(server interface smi_if i, unsigned phy_address, smi_ports_t &smi)
{
  if (SMI_MDIO_RESET_MUX) {
    timer tmr;
    int t;
    smi.p_smi_mdio <: 0x0;
    tmr :> t;tmr when timerafter(t+100000) :> void;
    smi.p_smi_mdio <: SMI_MDIO_REST;
  }

  if (isnull(smi.p_smi_mdio)) {
    smi.p_smi_mdc <: 1 << SMI_MDC_BIT;
  }
  else {
    smi.p_smi_mdc <: 1;
  }
  while (1) {
    select {
    case i.readwrite_reg(unsigned reg, unsigned val, int inning) -> int res:
      // Register access: lots of 1111, then a code (read/write), phy address,
      // register, and a turn-around, then data.
      smi_bit_shift(smi, 0xffffffff, 32, SMI_WRITE);         // Preamble
      smi_bit_shift(smi, (5+inning) << 10 | phy_address << 5 | reg,
                    14, SMI_WRITE);
      smi_bit_shift(smi, 2, 2, inning);
      res = smi_bit_shift(smi, val, 16, inning);
      break;
    }
  }
}


extends client interface smi_if : {

  unsigned get_phy_id(client smi_if i) {
    unsigned lo = i.read_reg(PHY_ID1_REG);
    unsigned hi = i.read_reg(PHY_ID2_REG);
    return ((hi >> 10) << 16) | lo;
  }

  void configure_phy(client smi_if i, int is_eth_100, int is_auto)
  {
    if (is_auto) {
      int autoNegAdvertReg;
      autoNegAdvertReg = i.read_reg(AUTONEG_ADVERT_REG);

      // Clear bits [9:5]
      autoNegAdvertReg &= 0xfc1f;

      // Set 100 or 10 Mpbs bits
      if (is_eth_100) {
        autoNegAdvertReg |= 1 << AUTONEG_ADVERT_100_BIT;
      } else {
        autoNegAdvertReg |= 1 << AUTONEG_ADVERT_10_BIT;
      }

      // Write back
      i.write_reg(AUTONEG_ADVERT_REG, autoNegAdvertReg);
    }

    int basicControl = i.read_reg(BASIC_CONTROL_REG);
    if (is_auto) {
      // set autoneg bit
      basicControl |= 1 << BASIC_CONTROL_AUTONEG_EN_BIT;
      i.write_reg(BASIC_CONTROL_REG, basicControl);
      // restart autoneg
      basicControl |= 1 << BASIC_CONTROL_RESTART_AUTONEG_BIT;
    }
    else {
      // set duplex mode, clear autoneg and 100 Mbps.
      basicControl |= 1 << BASIC_CONTROL_FULL_DUPLEX_BIT;
      basicControl &= ~( (1 << BASIC_CONTROL_AUTONEG_EN_BIT)|
                         (1 << BASIC_CONTROL_100_MBPS_BIT));
      if (is_eth_100) {                // Optionally set 100 Mbps
        basicControl |= 1 << BASIC_CONTROL_100_MBPS_BIT;
      }
    }
    i.write_reg(BASIC_CONTROL_REG, basicControl);
  }

  void set_loopback_mode(client smi_if i, int enable) {
    int controlReg = i.read_reg(BASIC_CONTROL_REG);

    // First clear both autoneg and loopback
    controlReg = controlReg & ~ ((1 << BASIC_CONTROL_AUTONEG_EN_BIT) |
                                 (1 << BASIC_CONTROL_LOOPBACK_BIT));
    // Now selectively set one of them
    if (enable) {
        controlReg = controlReg | (1 << BASIC_CONTROL_LOOPBACK_BIT);
    } else {
        controlReg = controlReg | (1 << BASIC_CONTROL_AUTONEG_EN_BIT);
    }

    i.write_reg(BASIC_CONTROL_REG, controlReg);
  }

  ethernet_link_state_t get_link_state(client smi_if i) {
    int link_up = ((i.read_reg(BASIC_STATUS_REG) >> BASIC_STATUS_LINK_BIT) & 1);
    return (link_up ? ETHERNET_LINK_UP : ETHERNET_LINK_DOWN);
  }

}
