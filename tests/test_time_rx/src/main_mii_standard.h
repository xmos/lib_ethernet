// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved

void test_rx(client interface mii_if i_mii,
             client control_if ctrl)
{
  int num_bytes = 0;
  int num_packets = 0;
  unsafe {
    int done = 0;
    mii_info_t mii_info = i_mii.init();
    while (!done) {
     #pragma ordered
     select {
      case mii_incoming_packet(mii_info):
        int * unsafe data = NULL;
        do {
          int nbytes;
          unsigned timestamp;
          {data, nbytes, timestamp} = i_mii.get_incoming_packet();
          if (data) {
            num_bytes += nbytes;
            num_packets += 1;
            i_mii.release_packet(data);
          }
        } while (data != NULL);
        break;

      case ctrl.status_changed():
        status_t status;
        ctrl.get_status(status);
        if (status == STATUS_DONE)
          done = 1;
          break;
      }
    }
  }
  debug_printf("Received %d packets, %d bytes\n", num_packets, num_bytes);
  ctrl.set_done();
}

#define NUM_CFG_IF 1

int main()
{
  control_if i_ctrl[NUM_CFG_IF];
  interface mii_if i_mii;
  par {
    // Having 2300 words gives enough for 3 full-sized frames in each bank of the
    // lite buffers. (4500 bytes * 2) / 4 => 2250 words.
    on tile[0]: mii(i_mii,
                    p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv, p_eth_txclk,
                    p_eth_txen, p_eth_txd, p_eth_dummy,
                    eth_rxclk, eth_txclk, 2300)
    on tile[0]: test_rx(i_mii, i_ctrl[0]);

    on tile[0]: control(p_ctrl, i_ctrl, NUM_CFG_IF, NUM_CFG_IF);

    on tile[0]: filler(0x22);
    on tile[0]: filler(0x33);
    on tile[0]: filler(0x44);
    on tile[0]: filler(0x55);
    on tile[0]: filler(0x66);
  }
  return 0;
}
