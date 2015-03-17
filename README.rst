Ethernet MAC library
====================

.. rheader::

   Ethernet MAC |version|

Ethernet MAC library
--------------------

The Ethernet MAC library provides a complete, software defined, Ethernet MAC that supports
10/100/1000 Mb/s data rates and is designed to IEEE Std 802.3-2002 specifications.

Features
........

  * 10/100/1000 Mb/s full-duplex operation
  * Media Independent Interface (MII) and Reduced Gigabit Media Independent Interface (RGMII) to the physical layer
  * Configurable Ethertype and MAC address filters for unicast, multicast and broadcast addresses
  * Frame alignment, CRC, and frame length error detection
  * IEEE 802.1Q Audio Video Bridging priority queueing and credit based traffic shaper
  * Support for VLAN-tagged frames
  * Transmit and receive frame timestamp support for IEEE 1588 and 802.1AS
  * Management Data Input/Output (MDIO) Interface for physical layer management

Components
...........

.. sidebysidelist::

 * 10/100 Mb/s Ethernet MAC
 * 10/100 Mb/s Ethernet MAC with real-time features
 * 10/100/1000 Mb/s Ethernet MAC with real-time features (xCORE-200 XE/XEF)
 * Raw MII interface

Software version and dependencies
.................................

.. libdeps::
