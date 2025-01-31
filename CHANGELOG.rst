lib_ethernet change log
=======================

4.0.0
-----

  * ADDED: RMII Ethernet MAC support for XCORE-AI
  * ADDED: Extended sim tests for testing RMII applications
  * ADDED: Support for running MII sim tests for XS3 architecture
  * ADDED: Support for XCommon CMake build system
  * ADDED: Exit command to RMII RT MAC
  * ADDED: Improved MAC feature documentation
  * ADDED: Tests for SMI
  * ADDED: Optional credit limit for Qav shaper
  * ADDED: Support for running MII sim tests for XS3 architecture
  * CHANGED: SMI re-write. Single port version now functional and 
             documented
  * CHANGED: Moved example PHY drivers to lib_board_support
  * REMOVED: Slicekit based examples because hardware is obsolete
  * REMOVED: Support for waf build system
  * REMOVED: Support for XS1 devices
  * RESOLVED: Build warnings even when compile successful
  * RESOLVED: Qav shaper credit overflow causing negative credit on idle
  * RESOLVED: Packets might not be transmitted for 21 seconds if
              no transmit activity for 21 seconds (IFG timer)

  * Changes to dependencies:

    - lib_gpio: Removed dependency

    - lib_locks: 2.0.0 -> 2.3.1

    - lib_logging: 2.0.0 -> 3.3.1

    - lib_otpinfo: Removed dependency

    - lib_slicekit_support: Removed dependency

    - lib_xassert: 2.0.0 -> 4.3.1

3.5.0
-----

  * CHANGED: Use XMOS Public Licence Version 1

3.4.0
-----

  * RESOLVED: Fix crash caused by significant backpressure being applied to the
    mii_eternet_mac.
  * RESOLVED: Fix lockup in mii_eternet_mac due to bug in packet commit logic.
  * RESOLVED: Fix bug in mii_ethernet_rt_mac that would corrupt the packet
    length when buffers filled.
  * RESOLVED: Ensure interrupts are disabled in the RGMII low-level driver on
    speed changes.
  * RESOLVED: Clean up code to fix compiler signed/unsigned warnings.
  * CHANGE: Prevent packet drop from RGMII LP queue when there is no HP queue.

  * Changes to dependencies:

    - lib_otpinfo: Added dependency 2.0.1

    - lib_slicekit_support: Added dependency 2.0.1

3.3.1
-----

  * ADDED: Function to write SMI extended MMD registers that some PHYs use
  * ADDED: Function to reset PHY by writing bit 15 of SMI register 0

3.3.0
-----

  * CHANGE: Update dependencies
  * ADDED: Ability for the standard MII ethernet MAC to be able to provide link
    status notifications.
  * RESOLVED: Fix test_appdata that failed randomly due to timing changes
  * RESOLVED: Fix RT MII ethernet transmit being broken by a memory corruption
    caused by a race condition. It could cause random packet contents to be sent
    on the wire and invalid sized packets.
  * RESOLVED: Fix RT MII buffer read pointer wrapping over the write pointer and
    causing the MAC layer to crash when the ethernet clients were not keeping up
    with the packets being received.

3.2.0
-----

  * ADDED: Ability to enable link status notifications to the client
  * RESOLVED: Fix bug which caused random crashes
  * RESOLVED: Fix bug in RT MII which caused packet to delay for 21.4s when sent
    after no packets sent for > 21.4s

3.1.2
-----

  * RESOLVED: Fixes incorrect memset length on packet queue pointers array
  * CHANGE: Update to source code license and copyright

3.1.1
-----

  * RESOLVED: Fixed issue with application filter data not being forwarded to
    clients of 100Mb MACs

3.1.0
-----

  * ADDED: VLAN tag stripping option to RT 100Mb Ethernet MAC configuration
    interface

3.0.3
-----

  * CHANGED: Update RGMII port delays to use best candidate from testing

3.0.2
-----

  * RESOLVED: Improve interoperability of PHY speed and link detection via RGMII
    inter-frame data
  * RESOLVED: Fix 64-bit alignment of MII lite to prevent crash on XS2

3.0.1
-----

  * RESOLVED: Fixed issue with optimisation build flags not being overridden by
    the module
  * ADDED: Missing extern declaration for inline interface function
    send_timed_packet()
  * ADDED: Ability to override the number of Ethertype filters from the
    ethernet_conf.h

3.0.0
-----

  * CHANGE: Major rework of structure and API
  * ADDED: RGMII Gigabit Ethernet MAC support for xCORE-200

  * Changes to dependencies:

    - lib_gpio: Added dependency 1.0.0

    - lib_locks: Added dependency 2.0.0

    - lib_logging: Added dependency 2.0.0

    - lib_xassert: Added dependency 2.0.0

