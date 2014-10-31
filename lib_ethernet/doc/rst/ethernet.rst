Ethernet library
================

.. rheader::

   Ethernet |version|

Ethernet Library
----------------

The Ethernet library provides a complete Layer 2 Ethernet MAC.

Features
........

 * 100 MBit/s operation.
 * Flexible filtering and routing to multiple clients
 * Realtime MAC with priority queuing
 * Realtime MAC with traffic shaping

Components
...........

 * Ethernet MAC
 * Ethernet realtime MAC (includes support for priority queuing and
                          traffic shaping)

Resource Usage
..............

TODO

.. list-table::
   :header-rows: 1
   :class: wide vertical-borders horizontal-borders

   * - Component
     - Pins
     - Ports
     - Clock Blocks
     - Ram
     - Logical cores
   * - Ethernet MAC
     - ?
     - ?
     - ?
     - ?
     - 2
   * - Ethernet MAC (RT)
     - ?
     - ?
     - ?
     - ?
     - 5

Software version and dependencies
.................................

This document pertains to version |version| of the Ethernet library. It is
intended to be used with version 13.x of the xTIMEcomposer studio tools.

The library does not have any dependencies (i.e. it does not rely on any
other libraries).

Related application notes
.........................

TODO: sort out app notes

The following application notes use this library:

  * AN???? - How to use the Ethernet component

Hardware characteristics
------------------------

TODO

API
---

All Ethernet functions can be accessed via the ``ethernet.h`` header::

  #include <ethernet.h>

You will also have to add ``lib_ethernet`` to the
``USED_MODULES`` field of your application Makefile.

Ethernet components are instantiated as parallel tasks that run in a
``par`` statement. The application can connect via an interface
connection.

TODO DIAGRAM + Explanation of how to connect to MAC!!!
|newpage|

Creating an Ethernet instance
.............................

.. doxygenfunction:: mii_ethernet

|newpage|

.. doxygenfunction:: mii_ethernet_rt

|newpage|

The Ethernet configuration interface
....................................

.. doxygenenum:: ethernet_link_state_t

.. doxygeninterface:: ethernet_config_if

|newpage|

The Ethernet filtering callback interface
.........................................

.. doxygeninterface:: ethernet_filter_callback_if

|newpage|

The Ethernet data handling interface
....................................

.. doxygenenum:: eth_packet_type_t

.. doxygenstruct:: ethernet_packet_info_t

.. doxygeninterface:: ethernet_if
