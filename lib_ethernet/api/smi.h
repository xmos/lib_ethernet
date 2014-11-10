#ifndef _smi_h_
#define _smi_h_
#include <stdint.h>

typedef interface smi_if {
  uint16_t read_reg(uint8_t regnum);
  void write_reg(uint8_t regnum, uint16_t val);
} smi_if;

[[distributable]]
void smi(server interface smi_if i,
         unsigned device_addr,
         port p_mdio, port p_mdc);

[[distributable]]
void smi_singleport(server interface smi_if i,
                    unsigned device_addr,
                    port p_smi,
                    unsigned mdio_bit, unsigned mdc_bit);


void smi_configure(client smi_if smi, int is_eth_100, int is_auto_negotiate);

void smi_set_loopback_mode(client smi_if smi, int enable);

unsigned smi_get_id(client smi_if smi);

int smi_is_link_up(client smi_if smi);


#endif // _smi_h_
