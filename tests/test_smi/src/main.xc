// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "smi.h"
#include <stdio.h>
#include "debug_print.h"
#include "syscall.h"

#include "ports.h"

void test_smi(client interface smi_if i_smi){
    delay_microseconds(1);
    p_phy_rst_n <: 0xf;
    delay_microseconds(1);

//   uint16_t read_reg(uint8_t phy_address, uint8_t reg_address);
    i_smi.write_reg(0x01, 0x02, 0x1234);

    uint16_t read = i_smi.read_reg(0x10, 0x11);
    printf("READ: 0x%u\n", read);
}


int main()
{
    interface smi_if i_smi;
    p_phy_rst_n <: 0;
    par {
        test_smi(i_smi);
        [[distribute]]
        smi(i_smi, p_smi_mdio, p_smi_mdc);
        par(int i = 0; i < 7; i++){while(1);}
    }
    return 0;
}

