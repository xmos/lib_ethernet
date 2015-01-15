#include <xs1.h>

#define RGMII_DELAY 0
#define RGMII_DIVIDE_1G 3
#define RGMII_DELAY_100M 0
#define RGMII_DIVIDE_100M (((RGMII_DIVIDE_1G + 1) * 5) - 1)

#ifndef INITIAL_MODE
  #define INITIAL_MODE INBAND_STATUS_1G_FULLDUPLEX
#endif

// The inter-frame gap is 96 bit times (1 clock tick at 100Mb/s). However,
// the EOF time stamp is taken when the last but one word goes into the
// transfer register, so that leaves 96 bits of data still to be sent
// on the wire (shift register word, transfer register word, crc word).
// In the case of a non word-aligned transfer compensation is made for
// that in the code at runtime.
// The adjustment is due to the fact that the instruction
// that reads the timer is the next instruction after the out at the
// end of the packet and the timer wait is an instruction before the
// out of the pre-amble
#if INITIAL_MODE == INBAND_STATUS_1G_FULLDUPLEX
#define RGMII_DIVIDE RGMII_DIVIDE_1G
#else
#define RGMII_DIVIDE RGMII_DIVIDE_100M
#endif 

#define ETHERNET_IFS_AS_REF_CLOCK_COUNT  ((96 + 96 - 10) * (RGMII_DIVIDE + 1)/2)

inline void enable_rgmii (unsigned delay, unsigned divide) {
#if defined(__XS2A__)
  unsigned int rdata;
  rdata = getps(XS1_PS_XCORE_CTRL0); 
  
  // Clear RGMII enable to get a posedge
  setps(XS1_PS_XCORE_CTRL0,  XS1_XCORE_CTRL0_RGMII_ENABLE_SET(rdata, 0x0));
  // Set all control values now
  setps(XS1_PS_XCORE_CTRL0, XS1_XCORE_CTRL0_RGMII_DELAY_SET (
        XS1_XCORE_CTRL0_RGMII_DIVIDE_SET( 
          XS1_XCORE_CTRL0_RGMII_ENABLE_SET(rdata, 0x1), divide), delay));
#else
  __builtin_trap();
#endif
}