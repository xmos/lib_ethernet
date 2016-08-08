// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#ifndef __mii_driver_h__
#define __mii_driver_h__

#ifdef __XC__

#define KERNELSTACKWORDS 128

typedef struct mii_lite_data_t {                    // DO NOT CHANGE LOCATIONS OR ADD ANY FIELDS.
    int next_buffer;
    int packet_in_lld;
    unsafe chanend notification_channel_end;
    unsafe chanend mii_channel_end;
    int mii_packets_overran;
    int refill_bank_number;
    int free_ptr[2], wr_ptr[2], last_safe_ptr[2], first_ptr[2], read_ptr[2];
    char notify_last;
    char notify_seen;
    char pad0, pad1;
    unsigned read_bank;
    unsigned read_bank_rd_ptr;
    unsigned read_bank_wr_ptr;
    unsafe chanend mii_out_channel;
    long long kernel_stack[KERNELSTACKWORDS/2];
} mii_lite_data_t;

/** This function gives the MII layer a buffer space to buffer input
 * packets into. The buffer space must be at least 1520 words, but can be
 * longer to improve performance.
 *
 * \param this            Structure that contains persistent data for this MII connection.
 *
 * \param c_in            Channel that communicates with the low level input MII.
 *
 * \param c_notifications Channel end that synchronises the interrupt and user layers.
 *
 * \param buffer          Array of words that can be used for buffering.
 *
 * \param words           Number of words in the array.
 */
extern void mii_lite_buffer_init(struct mii_lite_data_t &this,
                                 chanend c_in, chanend c_notifications,
                                 chanend c_out, int buffer[], int words);

/** Function that closes down the MII thread. This function should not be
 * called between ``mii_out_packet()`` and ``mii_out_packet_done()``
 *
 * \param c_notifications Channel end that synchronised interrupt and user layers.
 *
 * \param c_in            Channel that communicates with the low level input input MII.
 *
 * \param c_out           Channel that communicates with the low level input output MII.
 */
void mii_lite_close(chanend c_notifications, chanend c_in, chanend c_out);

/** This function will obtain a buffer from the input queue, or 0 if there
 * is no packet awaiting processing. When the packet has been processed,
 * free_in_buffer() should be called to free the packet buffer.
 *
 * \param this             Structure that contains persistent data for this MII connection.
 * \param c_notifications  A channel-end that synchronises the user
 *
 * \return The address of the buffer, the number of bytes and the timestamp
 */
{char * unsafe, unsigned, unsigned} extern mii_lite_get_in_buffer(mii_lite_data_t &this,
                                                                  chanend c_notifications);

/** This function is called to informs the input layer that the packet has
 * been processed and that the buffer can be reused. The address should be
 * the number returned by mii_in_packet. Packets should be released in a
 * timly manner, and hte buffers are organised as a strict FIFO, so not
 * processing a packet for a prolonged period of time shall lead to packet
 * loss.
 *
 * \param this    Structure that contains persistent data for this MII connection.
 *
 * \param address The address of the buffer to be freed as returned by mii_get_in_buffer().
 */
extern void mii_lite_free_in_buffer(mii_lite_data_t &this, char * unsafe address);

/** This function should be called to block the receiving thread. This
 * function will return when something interesting has happened at the MII
 * layer, and after its return, mii_get_in_buffer can be called to test
 * whether a new packet is available, and mii_restart_buffer() must be
 * called.
 *
 * Note that this function can be one of the cases in a select statement,
 * enabling the user layer to deal with different event sources in a
 * non-deterministic manner.
 *
 * \param this            Structure that contains persistent data for
 *                        this MII connection.
 *
 * \param c_notifications A channel-end that synchronises the user
 * layer with the interrupt layer
 */
extern select mii_lite_notified(mii_lite_data_t &this, chanend c_notifications);

/** This function must be called every time that mii_notified() has returned
 * and a buffer has been freed. It is safe to call this function more
 * often, for example, prior to every select statement that contains
 * mii_notified().
 */
extern void mii_lite_restart_buffer(mii_lite_data_t &this);


/** Function that initialises the transmitter of output packets. To be
 * called with the channel end that is connected to the MII Low-Level
 * Driver.
 *
 * \param c_out   Output channel to the Low-Level Driver.
 */
void mii_lite_out_init(chanend c_out);

/** Function that will cause a packet to be transmitted. It must get an
 * array with an index into the array, a length of hte packet (in bytes),
 * and a channel to the low-level driver. The low level driver will append
 * a CRC around the packet. The function returns once the preamble is on
 * the wire. The function mii_output_packet_done() should be called to syncrhonise
 * with the end of the packet.
 *
 * \param c_out  Output channel to the Low-Level Driver.
 *
 * \param buf    Array that contains the message. That this is an array
 *               of words, that must contain the data in network order: fill
 *               it using (buf, unsigned char[]). The last three words
 *               beyond the end of the buffer will be modified.
 *
 * \param index  Index into the array that contains the first byte.
 *
 * \param length Length of message in bytes, excluding CRC, which will be added
 *               upon transmission.
 *
 * \returns      The time at which the message went onto the wire, measured in
 *               reference clock periods
 *
 */
int mii_lite_out_packet(chanend c_out, int * unsafe buf, int index, int length);

/** Function that will cause a packet to be transmitted. It must get an
 * address, a length of the packet (in bytes),
 * and a channel to the low-level driver. The low level driver will append
 * a CRC around the packet. The function returns once the preamble is on
 * the wire. The function mii_output_packet_done() should be called to syncrhonise
 * with the end of the packet.
 *
 * \param c_out  Output channel to the Low-Level Driver.
 *
 * \param buf    Address that contains the message. This must be
 *               word aligned, and must contain the data in network
 *               order. The last three
 *               words beyond the end of the buffer will be modified.
 *
 * \param length Length of message in bytes, excluding CRC, which will be added
 *               upon transmission.
 *
 * \returns      The time at which the message went onto the wire, measured in
 *               reference clock periods
 *
 */
int mii_lite_out_packet_(chanend c_out, int buf, int length);

/** Select function that must be called after a call to mii_out_packet(). Upon
 * return of this function the packet has been put on the wire in its
 * entirety, and the interframe gap has expired - the next call to
 * mii_out_packet can be made without blocking. The function can be called in
 * one of two ways: either as an ordinary function, or as a case in a
 * select statement as in "case mii_out_packet_done(c_out);".
 *
 * \param c_out  Output channel to the Low-Level Driver.
 */
#pragma select handler
void mii_lite_out_packet_done(chanend c_out);


/** This function runs the MII low level driver. It requires at least 62.5
 * MIPS in order to be able to transmit and receive MII packets
 * simultaneously. The function has two channels to interface it to the
 * client functions that must run on a different thread on the same core.
 * The input and output client functions may run in the same thread or in
 * different threads.
 *
 *  \param p_rxd   RX data port
 *  \param p_rxdv  RX data valid port
 *  \param p_txd   TX data port
 *  \param p_mii_timing Dummy timing port
 *  \param c_in    input channel to the client thread.
 *  \param c_out   output channel to the client thread.
 */
void mii_lite_driver(in buffered port:32 p_rxd,
                     in port p_rxdv,
                     out buffered port:32 p_txd,
                     port p_mii_timing,
                     chanend c_in, chanend c_out);


#endif

#endif


