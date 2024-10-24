#include <platform.h>
#include <xs1.h>
#include <stdio.h>

port port_butt = on tile[0]: XS1_PORT_4D;
port port_led  = on tile[0]: XS1_PORT_4C; // Also RST_N

port p_mdc = on tile[0]: XS1_PORT_1N;
port p_mdio = on tile[0]: XS1_PORT_1O;

port p_rxdv = on tile[1] : XS1_PORT_1A;
port p_txen = on tile[1] : XS1_PORT_1B;
port p_rxer = on tile[1] : XS1_PORT_1C;
port p_clkin = on tile[1] : XS1_PORT_1D;
port p_rxclk = on tile[1] : XS1_PORT_1M;
port p_txclk = on tile[1] : XS1_PORT_1O;
port p_tx = on tile[1] : XS1_PORT_4A;
port p_rx = on tile[1] : XS1_PORT_4B;

int wait_for_button(){
    unsigned port_val;
    port_butt :> port_val;
    while(1){
        port_butt when pinsneq(port_val) :> port_val;
        if((port_val & 0x1) == 0){
            // printf("Button\n");
            for(int i = 0; i < 4; i++){
                port_led <: 0x1;
                delay_milliseconds(50);
                port_led <: 0x0;
                delay_milliseconds(50);
            }
            return 0;
        }
        if((port_val & 0x2) == 0){
            return 1;
        }
    }
    return 0;
}

void waggle(port p){
    unsigned width = 1;
    unsafe{width = (unsigned)p >> 16;} // Width is 3rd byte
    for(int i = 0; i < width; i++){
        if(width > 1) printf("Bit: %d\n", i);
        unsigned val = 0x1 << i;
        for(int i = 0; i < 10; i++){
            p <: val;
            delay_milliseconds(50);
            p <: 0x0;
            delay_milliseconds(50);
        }
    }
    p :> int _;
}

void do_io(port p, char *str){
    printf("Selected: %s\n", str);
    while(1){
        int ret = wait_for_button();

        if(ret == 0){
            printf("Toggle: %s\n", str);
            waggle(p);
        }
        if(ret == 1){
            return;
        }
    }
}

void do_io_rem(chanend c, port p, char *str){
    int cmd;
    c :> cmd;
    printf("Selected: %s\n", str);
    c <: 0;
    while(1){
        c :> cmd;
        if(cmd == 0){
            c <: 0;
            printf("Toggle: %s\n", str);
            waggle(p);
        } else {
            return;
        }
    }
}


void do_serv(chanend c_ctl){
    while(1){
        int cmd = wait_for_button();
        c_ctl <: cmd;
        c_ctl :> cmd;
        if(cmd == 2){
            return;
        }
    }
}


void rem(chanend c){
    while(1){
        do_io_rem(c, p_rxdv, "p_rxdv");
        c <: 1;
        do_io_rem(c, p_txen, "p_txen");
        c <: 1;
        do_io_rem(c, p_rxer, "p_rxer");
        c <: 1;
        do_io_rem(c, p_clkin, "p_clkin");
        c <: 1;
        do_io_rem(c, p_rxclk, "p_rxclk");
        c <: 1;
        do_io_rem(c, p_txclk, "p_txclk");
        c <: 1;
        do_io_rem(c, p_tx, "p_tx");
        c <: 1;
        do_io_rem(c, p_rx, "p_rx");
        c <: 2;     
    }
}

void ctl(chanend c_ctl){
    while(1){
        do_io(p_mdc, "p_mdc");
        do_io(p_mdio, "p_mdio");
        do_serv(c_ctl);
    }
}


int main(void){
    chan c_ctl;

    par{
        on tile[0]: ctl(c_ctl);
        on tile[1]: rem(c_ctl);
    }
    return 0;
}