#include <xs1.h>
#include <platform.h>
#include <stdlib.h>
#include <xscope.h>
#include <string.h>
#include <assert.h>
#include "debug_print.h"
#include "xscope_control.h"

#define XSCOPE_ID_CONNECT (0) // TODO duplicated currently
#define XSCOPE_ID_COMMAND_RETURN (1) // TODO duplicated currently

void xscope_control(chanend c_xscope, chanend c_clients[num_clients], static const unsigned num_clients)
{
    xscope_mode_lossless();
    xscope_connect_data_from_host(c_xscope);
    //wait for a ready from all clients
    unsigned ready[num_clients] = {0};
    unsigned num_ready = 0;
    unsigned done = 0;

    while(!done)
    {
        select {
            case ( size_t i = 0; i < num_clients; i ++) c_clients[i] :> int r:
                // debug_printf("Client ready: %d\n", i);
                assert(r == 1);
                assert(ready[i] == 0);
                ready[i] = r;
                num_ready += 1;
                if(num_ready == num_clients)
                {
                    done = 1;
                }
                break;
        }
    }
    unsigned char connect = 1;
    debug_printf("Indicate ready to host\n");
    xscope_bytes(XSCOPE_ID_CONNECT, 1, &connect);

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
                if(char_ptr[0] == CMD_DEVICE_SHUTDOWN)
                {
                    // Shutdown each client
                    for(int i=0; i<num_clients; i++)
                    {
                        c_clients[i] <: CMD_DEVICE_SHUTDOWN;
                        c_clients[i] :> int temp;
                        debug_printf("shutdown: %d\n", i);

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
                    c_clients[1+client_index] <: CMD_SET_DEVICE_MACADDR;
                    for(int i=0; i<6; i++) // c_clients index is one more than the client_index req by the host, since c_clients[0] is for lan8710a_phy_driver
                    {
                        c_clients[1+client_index] <: char_ptr[2+i];
                    }
                    c_clients[1+client_index] :> int temp;
                    // Acknowledge
                    unsigned char ret = 0;
                    xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                }
                else if(char_ptr[0] == CMD_SET_HOST_MACADDR)
                {
                    unsigned client_index = char_ptr[1];
                    debug_printf("set host mac address\n");
                    for(int i=0; i<6; i++)
                    {
                        debug_printf("%2x ",char_ptr[1+i]);
                    }
                    debug_printf("\n");
                    // send it to all client except the lan8710a_phy_driver
                    for(int cl=1; cl<num_clients; cl++)
                    {
                        c_clients[cl] <: CMD_SET_HOST_MACADDR;
                        for(int i=0; i<6; i++) // c_clients index is one more than the client_index req by the host, since c_clients[0] is for lan8710a_phy_driver
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
                    debug_printf("set dut tx packets client: %u %u %u\n", client_index, arg1, arg2);

                    c_clients[1+client_index] <: CMD_HOST_SET_DUT_TX_PACKETS;
                    c_clients[1+client_index] <: arg1;
                    c_clients[1+client_index] <: arg2;
                    // Acknowledge host app
                    unsigned char ret = 0;
                    xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                }
                else if(char_ptr[0] == CMD_SET_DUT_RECEIVE)
                {
                    unsigned client_index = char_ptr[1];
                    unsigned recv_flag = char_ptr[2];
                    c_clients[1+client_index] <: CMD_SET_DUT_RECEIVE;
                    c_clients[1+client_index] <: recv_flag;
                    c_clients[1+client_index] :> int temp;
                    // Acknowledge
                    unsigned char ret = 0;
                    xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                }
                break;
        }
    }
}
