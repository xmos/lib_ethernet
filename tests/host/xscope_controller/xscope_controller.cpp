#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <assert.h>
#ifdef _WIN32
#include <Winsock2.h>
#include <windows.h>
#else
#include <unistd.h>
#endif
#include <errno.h>
#include <sstream>
#include <vector>
#include <iostream>
#include <xscope_endpoint.h>


enum {
    CMD_DEVICE_SHUTDOWN = 1,
    CMD_SET_DEVICE_MACADDR,
    CMD_SET_HOST_MACADDR
};

#define LINE_LENGTH 1024

#define XSCOPE_ID_CONNECT (0)
#define XSCOPE_ID_COMMAND_RETURN (1)

int connected = 0;

#define RET_NO_RESULT (255)
unsigned char ret = RET_NO_RESULT;

static char get_next_char(const char **buffer)
{
    const char *ptr = *buffer;
    while (*ptr && isspace(*ptr)) {
        ptr++;
    }

    *buffer = ptr + 1;
    return *ptr;
}

static int convert_atoi_substr(const char **buffer)
{
    const char *ptr = *buffer;
    unsigned int value = 0;
    while (*ptr && isspace(*ptr)) {
        ptr++;
    }

    if (*ptr == '\0') {
        return 0;
    }

    value = atoi((char*)ptr);

    while (*ptr && !isspace(*ptr)) {
        ptr++;
    }

    *buffer = ptr;
    return value;
}

std::vector<unsigned char> parse_mac_address(std::string mac)
{
    std::vector<unsigned char> mac_bytes;
    // Parse a string like "a4:ae:12:77:86:97" into a vector containing the 6 mac address bytes
    std::stringstream ss(mac);
    std::string byte;

    while (std::getline(ss, byte, ':')) {  // Split by ':'
        mac_bytes.push_back(static_cast<uint8_t>(std::stoi(byte, nullptr, 16)));  // Convert hex to int
    }

    std::cout << "Parsed MAC address bytes: ";
    for (uint8_t b : mac_bytes) {
        std::cout << std::hex << static_cast<int>(b) << " ";
    }
    std::cout << std::endl;
    return mac_bytes;
}

#define COMMAND_RESPONSE_POLL_MS (1)
#define COMMAND_RESPONSE_TIMEOUT_MS (3000)
#define COMMAND_RESPONSE_ITERS (COMMAND_RESPONSE_TIMEOUT_MS / COMMAND_RESPONSE_POLL_MS)
unsigned char wait_for_command_response()
{
    for (int i = 0; i < COMMAND_RESPONSE_ITERS; ++i) {
#ifdef _WIN32
        Sleep(COMMAND_RESPONSE_POLL_MS);
#else
        usleep(COMMAND_RESPONSE_POLL_MS * 1000);
#endif

        if (ret != RET_NO_RESULT) {
            if (ret != 0)
                fprintf(stderr, "Command failed, error code %u\n", ret);
            return ret;
        }
    }

    fprintf(stderr, "Timed out waiting for command response\n");
    return RET_NO_RESULT;
}

void xscope_print(unsigned long long timestamp,
                  unsigned int length,
                  unsigned char *data) {
    if (length) {
        for (unsigned i = 0; i < length; i++) {
            fprintf(stderr, "%c", *(&data[i]));
            fflush(stderr);
        }
    }
}

void xscope_record(unsigned int id,
                   unsigned long long timestamp,
                   unsigned int length,
                   unsigned long long dataval,
                   unsigned char *databytes)
{
    switch(id) {
    case XSCOPE_ID_CONNECT:
        if (length != 1) {
            fprintf(stderr, "unexpected length %u in connection response\n", length);
            return;
        }
        connected = 1;
        return;

    case XSCOPE_ID_COMMAND_RETURN:
        if (length != 1) {
            fprintf(stderr, "unexpected length %u in command response\n", length);
            return;
        }
        ret = databytes[0];
        return;

   default:
       fprintf(stderr, "xscope_record: unexpected ID %u\n", id);
       return;
   }
}

#define CONNECT_POLL_MS (1)
#define CONNECT_TIMEOUT_MS (10000)
#define CONNECT_ITERS (CONNECT_TIMEOUT_MS / CONNECT_POLL_MS)

int main(int argc, char *argv[]) {
    /* Having run with the xscope-port argument all prints from the xCORE
     * will be directed to the socket, so they need to be printed from here
     */
    xscope_ep_set_print_cb(xscope_print);

    xscope_ep_set_record_cb(xscope_record);

    if (argc > 3) {
        /* argv[1] = ip address
         * argv[2] = port number
         * argv[3] = command
         */
        xscope_ep_connect(argv[1], argv[2]);

        if(strcmp(argv[3], "connect") == 0)
        {
            int iters = 0;
            while(1) {
    #ifdef _WIN32
                Sleep(CONNECT_POLL_MS);
    #else
                usleep(CONNECT_POLL_MS * 1000);
    #endif

                if (connected)
                    break;

                ++iters;
                if (iters == CONNECT_ITERS) {
                    fprintf(stderr, "Timed out waiting for xSCOPE connection handshake\n");
                    return 1;
                }
            }
        } // if(strcmp(argv[3], "connect") == 0)
        else if(strcmp(argv[3], "shutdown") == 0)
        {
            unsigned char to_send[1];
            to_send[0] = CMD_DEVICE_SHUTDOWN;
            fprintf(stderr, "xscope_controller sending cmd CMD_DEVICE_SHUTDOWN\n");
            while (xscope_ep_request_upload(1, (unsigned char *)&to_send) != XSCOPE_EP_SUCCESS);
            unsigned char result = wait_for_command_response();
            if (result != 0)
            {
                return 1;
            }
        }
        else if(strcmp(argv[3], "set_dut_macaddr") == 0)
        {
            if(argc != 6)
            {
                fprintf(stderr, "Incorrect usage of set_dut_macaddr command\n");
                fprintf(stderr, "Usage: host_address port set_dut_macaddr <client_index> <mac_addr, eg. 00:11:22:33:44:55>\n");
                return 1;
            }

            unsigned client_id = std::atoi(argv[4]);
            std::vector<unsigned char> dut_mac_bytes = parse_mac_address(argv[5]);
            static const int cmd_bytes = 8;
            unsigned char to_send[cmd_bytes];
            to_send[0] = CMD_SET_DEVICE_MACADDR;
            to_send[1] = client_id;
            for(int i=0; i<6; i++)
            {
                to_send[2+i] = dut_mac_bytes[i];
            }
            while (xscope_ep_request_upload(cmd_bytes, (unsigned char *)&to_send) != XSCOPE_EP_SUCCESS);
            unsigned char result = wait_for_command_response();
            if (result != 0)
            {
                return 1;
            }
        }
        else if(strcmp(argv[3], "set_host_macaddr") == 0)
        {
            if(argc != 5)
            {
                fprintf(stderr, "Incorrect usage of set_host_macaddr command\n");
                fprintf(stderr, "Usage: host_address port set_host_macaddr <mac_addr, eg. 62:57:4a:b7:35:c8>\n");
                return 1;
            }

            std::vector<unsigned char> host_mac_bytes = parse_mac_address(argv[4]);
            static const int cmd_bytes = 7;
            unsigned char to_send[cmd_bytes];
            to_send[0] = CMD_SET_HOST_MACADDR;
            for(int i=0; i<6; i++)
            {
                to_send[1+i] = host_mac_bytes[i];
            }
            while (xscope_ep_request_upload(cmd_bytes, (unsigned char *)&to_send) != XSCOPE_EP_SUCCESS);
            unsigned char result = wait_for_command_response();
            if (result != 0)
            {
                return 1;
            }
        }
    } else {
        fprintf(stderr, "Usage: host_address port [commands to send via xscope...]\n");
        return 1;
    }

    fprintf(stderr, "Shutting down...\n");
    fflush(stderr);
    xscope_ep_disconnect();

    return 0;
}
