// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "smi.h"
#include <stdio.h>
#include <print.h>
#include "syscall.h"

#include "ports.h"

// Adding these here instead of ports.h since they conflict with
// test ports (XS1_PORT_1N is the same as p_rx_lp_control[1] used in test_rx_queues and test_avb).
// These are smi testing specific so okay to not include in the common includes file
port p_smi_mdio   = on tile[0]: XS1_PORT_1M;
port p_smi_mdc    = on tile[0]: XS1_PORT_1N;
port p_smi_mdc_mdio = on tile[0]: XS1_PORT_4B;
port p_phy_rst_n  = on tile[0]: XS1_PORT_4A;
#define SMI_SINGLE_PORT_MDC_BIT     0
#define SMI_SINGLE_PORT_MDIO_BIT    1

void test_smi(client interface smi_if i_smi){
    delay_microseconds(1);
    p_phy_rst_n <: 0xf;
    delay_microseconds(1);

    for(int i = 0; i < 3; i++){
        uint16_t word_to_tx = i + (i << 4) + (i << 8) + (i << 12);
        i_smi.write_reg(0x03, 0x0a, word_to_tx);
    }

    for(int i = 0; i < 3; i++){
        uint16_t read = i_smi.read_reg(0x10, 0x11);
        printf("DUT READ: 0x%x\n", read);
    }

    p_phy_rst_n <: 0; // This terminates the test
}


int main()
{
    interface smi_if i_smi;
    p_phy_rst_n <: 0;
    par {
        test_smi(i_smi);
        [[distribute]]
#if TWO_PORTS
        smi(i_smi, p_smi_mdio, p_smi_mdc);
#elif SINGLE_PORT
        smi_singleport(i_smi, p_smi_mdc_mdio, SMI_SINGLE_PORT_MDIO_BIT, SMI_SINGLE_PORT_MDC_BIT);
#endif
        par(int i = 0; i < 7; i++){while(1);}
    }
    return 0;
}

