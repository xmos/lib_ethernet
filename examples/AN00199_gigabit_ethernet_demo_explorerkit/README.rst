:orphan:

####################################################
XMOS Gigabit Ethernet application note (eXplorerKIT)
####################################################

*******
Summary
*******

Ethernet connectivity is an essential part of the explosion of connected devices known collectively as the Internet of Things (IoT).
XMOS technology is perfectly suited to these applications - offering future proof and reliable ethernet connectivity whilst offering the flexibility to interface to a huge variety of "Things".

This application note shows a simple example that demonstrates the use
of the XMOS Ethernet library to create a *gigabit* layer 2 ethernet MAC
interface on an XMOS multicore microcontroller.

The code associated with this application note provides an example of
using the Ethernet Library to provide a framework for the creation of an
ethernet Reduced Gigabit Media Independent Interface (RGMII) and
MAC interface for gigabit data rates.

The applcation note uses XMOS libraries to provide a simple IP stack
capable of responding to an ICMP ping message. The code used in the
application note provides both MII communication to the PHY and a MAC
transport layer for ethernet packets and enables a client to connect
to it and send/receive packets.

*****************
Required hardware
*****************

This application note is designed to run on an XMOS xCORE-200 series device.
The example code provided with the application has been implemented
and tested on the xCORE-200 Explorer development kit.
There is no dependancy on this board - it can be modified to run on
any xCORE-200 series device with gigabit Ethernet capability.

**************
Required tools
**************

  * XMOS XTC Tools: 15.3.1

*********************************
Required libraries (dependencies)
*********************************

  * `lib_ethernet <https://www.xmos.com/file/lib_ethernet>`_
  * `lib_otp_info <https://www.xmos.com/file/lib_otp_info>`_
  * `lib_board_support <https://www.xmos.com/file/lib_board_support>`_


*************
Prerequisites
*************

 * This document assumes familarity with the XMOS xCORE architecture,
   the Ethernet standards IEEE 802.3, the XMOS tool chain and
   the XC language. Documentation related to these aspects which are
   not specific to this application note are linked to in the
   references appendix.

 * For an overview of the Ethernet library, please see the Ethernet
   library user guide.


*******
Support
*******

This package is supported by XMOS Ltd. Issues can be raised against the software at: http://www.xmos.com/support
