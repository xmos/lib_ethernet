// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#ifndef __mii_h__
#define __mii_h__
#include <stddef.h>
#include <xs1.h>

#ifdef __XC__

/** Type containing internal state of the mii task.
 *
 *  This type contains internal state of the MII tasks. It is given to the
 *  application via the init() function of the 'mii_if' interface and
 *  its main use is to allow eventing on incoming packets via the
 *  mii_incominfg_packet() function.
 */
struct mii_lite_data_t;
typedef struct mii_lite_data_t * unsafe mii_info_t;

/** Interface allowing access to the MII packet layer.
 *
 */
typedef interface mii_if {
  /** Initialize the MII layer
   *
   *  This function initializes the MII layer. In doing so it will setup
   *  an interrupt handler on the current logical core that calls the function
   *  (so tasks on that core may be interrupted and can no longer rely on
   *  the deterministic runtime of the xCORE).
   *
   * \returns state structure to use in subsequent calls to send/receive
   *          packets.
   */
  mii_info_t init();

  /** Get incoming packet from MII layer.
   *
   *  This function can be called after an event is triggered by the
   *  mii_incoming_packet() function. It gets the next incoming packet
   *  from the packet buffer of the MII layer.
   *
   *  \returns a tuple containing a pointer to the data (which is owned
   *           by the application until the release_packet() function
   *           is called), the number of bytes in the packet and
   *           a timestamp. If no packet is available then the first
   *           element will be a NULL pointer.
   */
  {int * unsafe, size_t, unsigned} get_incoming_packet();

  /** Release a packet back to the MII layer.
   *
   *  This function will release a packet back to the MII layer to be
   *  used for buffering.
   *
   *  \param data The pointer to packet to return. This should be the
   *              same pointer returned by get_incoming_packet()
   */
  void release_packet(int * unsafe data);

  /** Send a packet to the MII layer.
   *
   *  This function will send a packet over MII. It does not block and will
   *  return immediately with the MII layer now owning the memory of the packet.
   *  The function mii_packet_sent() should be subsequently
   *  called to determine when the packet has been transmitted and the
   *  application can use the buffer again.
   *
   *  \param buf  The pointer to the packet to be transferred to the MII layer.
   *  \param n    The number of bytes in the packet to send.
   */
  void send_packet(int * unsafe buf, size_t n);
} mii_if;


/** Event on/wait for an incoming packet.
 *
 *  This function waits for an incoming packet from the MII layer.
 *  It can be used in a select to detect an incoming packet e.g
 *
    \verbatim
     mii_info_t mii_info = i_mii.init();
     select {
       case mii_incoming_packet(mii_info):
            ...
            break;
     ...
    \endverbatim
 *
 */
unsafe void mii_incoming_packet(mii_info_t info);

/** Event on/wait for a packet send to complete.
 *
 *  This function will wait for a packet transmitted with the ``send_packet``
 *  function on the mii_interface to complete.
 *  It can be used in a select to event when the transmission is complete e.g
 *
    \verbatim
     mii_info_t mii_info = i_mii.init();
     select {
       case mii_packet_sent(mii_info):
            ...
            break;
     ...
    \endverbatim
 */
unsafe void mii_packet_sent(mii_info_t info);

/** Raw MII component.
 *
 *  This function implements a MII layer component with a basic buffering scheme that
 *  is shared with the application. It provides a direct access to the MII pins. It does
 *  not implement the buffering and filtering required by a compliant Ethernet MAC layer,
 *  and defers this to the application.
 *
 *  The buffering of this task is shared with the application it is connected to.
 *  It sets up an interrupt handler on the logical core the application is running on
 *  via the ``init`` function on the `mii_if` interface connection) and also
 *  consumes some of the MIPs on that core in addition to the core `mii` is running on.
 *
 *  \param i_mii            The MII interface to connect to the application.
 *  \param p_rxclk          MII RX clock port
 *  \param p_rxer           MII RX error port
 *  \param p_rxd            MII RX data port
 *  \param p_rxdv           MII RX data valid port
 *  \param p_txclk          MII TX clock port
 *  \param p_txen           MII TX enable port
 *  \param p_txd            MII TX data port
 *  \param p_timing         Internal timing port - this can be any xCORE port that
 *                          is not connected to any external device.
 *  \param rxclk            Clock used for MII receive timing
 *  \param txclk            Clock used for MII transmit timing
 *  \param rx_bufsize_words The number of words to used for a receive buffer.
                            This should be at least 1500 words.
*/
void mii(server mii_if i_mii,
         in port p_rxclk, in port p_rxer, in port p_rxd,
         in port p_rxdv,
         in port p_txclk, out port p_txen, out port p_txd,
         port p_timing,
         clock rxclk,
         clock txclk,
         static const unsigned rx_bufsize_words);

#endif

#include "mii_impl.h"
#endif // __mii_h__
