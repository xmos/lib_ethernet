#include <xs1.h>
#include <platform.h>
#include <stdlib.h>
#include <xscope.h>
#include <assert.h>
#include "test_rx.h"
#include "debug_print.h"

#define XSCOPE_ID_CONNECT (0) // TODO duplicated currently
#define XSCOPE_ID_COMMAND_RETURN (1) // TODO duplicated currently

#define CMD_DEVICE_SHUTDOWN (1) // TODO duplicated currently


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
            case ( size_t i = 0; i < num_clients; i ++)
                c_clients[i] :> int r:
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
                        c_clients[i] <: 1;
                        c_clients[i] :> int temp;
                    }
                }

                // Acknowledge
                unsigned char ret = 0;
                xscope_bytes(XSCOPE_ID_COMMAND_RETURN, 1, &ret);
                return;
                break;

        }
    }




}
