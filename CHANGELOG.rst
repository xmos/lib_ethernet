Ethernet MAC library change log
===============================

3.0.1
-----
  * Fixed issue with optimisation build flags not being overriden by the module
  * Added missing extern declaration for inline interface function send_timed_packet()
  * Added ability to override the number of Ethertype filters from the ethernet_conf.h

3.0.0
-----
  * Major rework of structure and API
  * Added RGMII Gigabit Ethernet MAC support for xCORE-200