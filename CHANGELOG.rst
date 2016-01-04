Ethernet MAC library change log
===============================

3.1.1
-----

  * Fixed issue with application filter data not being forwarded to clients of
    100Mb MACs

3.1.0
-----

  * Added VLAN tag stripping option to RT 100Mb Ethernet MAC configuration
    interface

3.0.3
-----

  * Update RGMII port delays to use best candidate from testing

3.0.2
-----

  * Improve interoperability of PHY speed and link detection via RGMII
    inter-frame data
  * Fix 64-bit alignment of MII lite to prevent crash on XS2

3.0.1
-----

  * Fixed issue with optimisation build flags not being overridden by the module
  * Added missing extern declaration for inline interface function
    send_timed_packet()
  * Added ability to override the number of Ethertype filters from the
    ethernet_conf.h

3.0.0
-----

  * Major rework of structure and API
  * Added RGMII Gigabit Ethernet MAC support for xCORE-200

  * Changes to dependencies:

    - lib_logging: Added dependency 2.0.0

    - lib_xassert: Added dependency 2.0.0

    - lib_gpio: Added dependency 1.0.0

    - lib_locks: Added dependency 2.0.0

