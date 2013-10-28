#include "ethernet.h"

[[distributable]]
void arp_ip_filter(server ethernet_filter_if i_filter)
{
  while (1) {
    select {
    case i_filter.do_filter(char buf[len], unsigned len) -> unsigned result:
      result = 0;
      unsigned short etype = ((unsigned short) buf[12] << 8) + buf[13];
      int qhdr = (etype == 0x0081);

      if (qhdr) {
        // has a 802.1q tag - read etype from next word
        etype = ((unsigned short) buf[16] << 8) + buf[17];
      }

      switch (etype) {
      case 0x0608:
      case 0x0008:
        result = 1;
        break;
      default:
        break;
      }
      break;
    }
  }
}
