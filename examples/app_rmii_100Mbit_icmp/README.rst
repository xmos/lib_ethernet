:orphan

#############################
100Mbit Ethernet RMII example
#############################

*******
Summary
*******

Ethernet connectivity is an essential part of the explosion of connected
devices known collectively as the Internet of Things (IoT).  XMOS technology is
perfectly suited to these applications - offering future proof and reliable
ethernet connectivity whilst offering the flexibility to interface to a huge
variety of "Things".

This example that demonstrates the use
of the XMOS Ethernet library to create a layer 2 ethernet MAC
interface on an XMOS multicore microcontroller.

The code associated with this application note provides an example of
using the Ethernet Library to provide a framework for the creation of an
ethernet Reduced Media Independent Interface (RMII) and MAC interface for
100Mbps.

The applcation note uses XMOS libraries to provide a simple IP stack
capable of responding to an ICMP ping message. The code used in the
application note provides both RMII communication to the PHY and a MAC
transport layer for ethernet packets and enables a client to connect
to it and send/receive packets.

*****************
Required hardware
*****************

The example code provided with this application has been implemented and tested
on the xk_eth_xu316_dual_100m board.

**************
Required tools
**************

  * XMOS XTC Tools: 15.3.1

*********************************
Required libraries (dependencies)
*********************************

  * `lib_ethernet <https://www.xmos.com/file/lib_ethernet>`_
  * `lib_xua <https://www.xmos.com/file/lib_xua>`_
  * `lib_board_support <https://www.xmos.com/file/lib_board_support>`_
  * `lib_otpinfo <https://www.xmos.com/file/lib_otpinfo>`_


*************
Prerequisites
*************

 * This document assumes familarity with the XMOS xCORE architecture,
   the Ethernet standards IEEE 802.3u (RMII), the XMOS tool chain and
   the XC language. Documentation related to these aspects which are
   not specific to this application note are linked to in the
   references appendix.

 * For an overview of the Ethernet library, please see the Ethernet
   library user guide.


*******
Support
*******

This package is supported by XMOS Ltd. Issues can be raised against the software at: http://www.xmos.com/support
