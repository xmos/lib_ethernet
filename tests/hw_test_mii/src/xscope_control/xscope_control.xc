#include <xs1.h>
#include <platform.h>
#include <stdlib.h>
#include <xscope.h>
#include <string.h>
#include <assert.h>
#include "debug_print.h"
#include "xscope_control.h"

#define XSCOPE_ID_COMMAND_RETURN (1) // TODO duplicated currently

static void wait_us(int microseconds)
{
    timer t;
    unsigned time;

    t :> time;
    t when timerafter(time + (microseconds * 100)) :> void;
}

void xscope_control(chanend c_xscope, chanend c_clients[num_clients], static const unsigned num_clients)
{
    xscope_mode_lossless();
    xscope_connect_data_from_host(c_xscope);

    unsigned int buffer[256/4]; // The maximum read size is 256 bytes
    unsigned char *char_ptr = (unsigned char *)buffer;
    int bytes_read = 0;

    while(1)
    {
        select{
            case xscope_data_from_host(c_xscope, (unsigned char *)buffer, bytes_read):
                if (bytes_read < 1) {
                    debug_printf("ERROR: Received '%d' bytes\n", bytes_read);
                    break;
                }
                if(char_ptr[0] == CMD_DEVICE_CONNECT)
                {
                    debug_printf("Received CMD_DEVICE_CONNECT\n");
                    // Shutdown each client
                    int ready = 0;
                    for(int i=0; i<num_clients; i++)
                    {
                        debug_printf("Check client %d ready\n", i);
                        c_clients[i] <: CMD_DEVICE_CONNECT;
                        c_clients[i] :> ready;
                        while(!ready)
                        {
                            wait_us(1000);
                            c_clients[i] <: CMD_DEVICE_CONNECT;
                            c_clients[i] :> ready;
                        };
                        debug_printf("Client %d ready\n", i);
                    }
                    // Acknowledge
                    unsigned char ret = 0;
                    xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                }
                if(char_ptr[0] == CMD_DEVICE_SHUTDOWN)
                {
                    // Shutdown each client
                    for(int i=0; i<num_clients; i++)
                    {
                        c_clients[i] <: CMD_DEVICE_SHUTDOWN;
                        c_clients[i] :> int temp;
                        debug_printf("shutdown: client %d\n", i);

                    }
                    // Acknowledge
                    unsigned char ret = 0;
                    xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                    return;
                }
                else if(char_ptr[0] == CMD_SET_DEVICE_MACADDR)
                {
                    unsigned client_index = char_ptr[1];
                    debug_printf("set mac address for client index %u\n", client_index);
                    for(int i=0; i<6; i++)
                    {
                        debug_printf("%2x ",char_ptr[2+i]);
                    }
                    debug_printf("\n");
                    c_clients[client_index] <: CMD_SET_DEVICE_MACADDR;
                    for(int i=0; i<6; i++)
                    {
                        c_clients[client_index] <: char_ptr[2+i];
                    }
                    c_clients[client_index] :> int temp;
                    // Acknowledge
                    unsigned char ret = 0;
                    xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                }
                else if(char_ptr[0] == CMD_SET_HOST_MACADDR)
                {
                    debug_printf("set host mac address\n");
                    for(int i=0; i<6; i++)
                    {
                        debug_printf("%2x ",char_ptr[1+i]);
                    }
                    debug_printf("\n");
                    // send it to all client except the lan8710a_phy_driver
                    for(int cl=0; cl<num_clients; cl++)
                    {
                        c_clients[cl] <: CMD_SET_HOST_MACADDR;
                        for(int i=0; i<6; i++)
                        {
                            c_clients[cl] <: char_ptr[1+i];
                        }
                        c_clients[cl] :> int temp;
                    }
                    // Acknowledge
                    unsigned char ret = 0;
                    xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                }
                else if(char_ptr[0] == CMD_HOST_SET_DUT_TX_PACKETS)
                {
                    unsigned client_index, arg1, arg2;
                    memcpy(&client_index, &char_ptr[1], sizeof(client_index));
                    memcpy(&arg1, &char_ptr[1 + sizeof(client_index)], sizeof(arg1));
                    memcpy(&arg2, &char_ptr[1 + sizeof(client_index) + sizeof(arg1)], sizeof(arg2));
                    debug_printf("set dut tx packets client %u: %u %u\n", client_index, arg1, arg2);

                    c_clients[client_index] <: CMD_HOST_SET_DUT_TX_PACKETS;
                    c_clients[client_index] <: arg1;
                    c_clients[client_index] <: arg2;
                    c_clients[client_index] :>  int temp;
                    // Acknowledge host app
                    unsigned char ret = 0;
                    xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                }
                else if(char_ptr[0] == CMD_SET_DUT_RECEIVE)
                {
                    unsigned client_index = char_ptr[1];
                    unsigned recv_flag = char_ptr[2];
                    c_clients[client_index] <: CMD_SET_DUT_RECEIVE;
                    c_clients[client_index] <: recv_flag;
                    c_clients[client_index] :> int temp;
                    // Acknowledge
                    unsigned char ret = 0;
                    xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                }
                else if(char_ptr[0] == CMD_EXIT_DEVICE_MAC)
                {
                    debug_printf("xscope_control received CMD_EXIT_DEVICE_MAC\n");
                    c_clients[0] <: CMD_EXIT_DEVICE_MAC; // Send to the first client.
                    c_clients[0] :> int temp;
                    // Acknowledge
                    unsigned char ret = 0;
                    xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                }
                else if(char_ptr[0] == CMD_SET_DUT_TX_SWEEP)
                {
                    debug_printf("xscope_control received CMD_SET_DUT_TX_SWEEP\n");
                    unsigned client_index = char_ptr[1];
                    debug_printf("set client index %u to do a TX sweep\n", client_index);
                    c_clients[client_index] <: CMD_SET_DUT_TX_SWEEP;
                    c_clients[client_index] :> int temp;
                    // Acknowledge
                    unsigned char ret = 0;
                    xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                }
                break;
        }
    }
}
