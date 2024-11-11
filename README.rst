:orphan:

########################
lib_adat: ADAT lightpipe
########################

:vendor: XMOS
:version: 2.0.1
:scope: General Use
:description: ADAT Lightpipe digital audio interface
:category: Audio
:keywords: Ethernet, MII, RGMII
:devices: xcore.ai, xcore-200

*******
Summary
*******


The Ethernet MAC library provides a complete, software defined, Ethernet MAC that supports
10/100/1000 Mb/s data rates and is designed to IEEE Std 802.3-2002 specifications.

 * 10/100 Mb/s Ethernet MAC
 * 10/100 Mb/s Ethernet MAC with real-time features
 * 10/100/1000 Mb/s Ethernet MAC with real-time features (xCORE-200 XE/XEF)
 * Raw MII interface

********
Features
********

  * 10/100/1000 Mb/s full-duplex operation
  * Media Independent Interface (MII) and Reduced Gigabit Media Independent Interface (RGMII) to the physical layer
  * Configurable Ethertype and MAC address filters for unicast, multicast and broadcast addresses
  * Frame alignment, CRC, and frame length error detection
  * IEEE 802.1Q Audio Video Bridging priority queueing and credit based traffic shaper
  * Support for VLAN-tagged frames
  * Transmit and receive frame timestamp support for IEEE 1588 and 802.1AS
  * Management Data Input/Output (MDIO) Interface for physical layer management

************
Known issues
************

Please see the active repo for up to date `known issues <https://github.com/xmos/lib_ethernet/issues>`_.

****************
Development repo
****************

  * `lib_ethernet <https://www.github.com/xmos/lib_ethernet>`_

**************
Required tools
**************

  * XMOS XTC Tools: 15.3.0

*********************************
Required libraries (dependencies)
*********************************

  * `lib_locks <https://www.github.com/xmos/lib_locks>`_
  * `lib_logging <https://www.github.com/xmos/lib_logging>`_
  * `lib_xassert <https://www.github.com/xmos/lib_xassert>`_

*************************
Related application notes
*************************

The following application notes use this library:

  * `AN00199: XMOS Gigabit Ethernet application note (eXplorerKIT) <https://www.xmos.com/file/an00199>`_
  * `AN00120: How to use the Ethernet MAC library <https://www.xmos.com/file/an00120-xmos-100mbit-ethernet-application-note>`_

*******
Support
*******

This package is supported by XMOS Ltd. Issues can be raised against the software at: http://www.xmos.com/support
