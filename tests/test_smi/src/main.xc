// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "smi.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#include "ports.h"

void test_smi(client interface smi_if i_smi){

//   uint16_t read_reg(uint8_t phy_address, uint8_t reg_address);
  // void write_reg(uint8_t phy_address, uint8_t reg_address, uint16_t val);
}


int main()
{
    interface smi_if i_smi;
    par {
        test_smi(i_smi);
        [[distribute]]
        smi(i_smi, p_smi_mdio, p_smi_mdc);
        par(int i = 0; i < 7; i++){while(1);}
    }
    return 0;
}

