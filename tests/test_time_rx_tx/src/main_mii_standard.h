// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved

#define NUM_PACKET_LENGTHS 64

#define HEADER_BYTES 14

static void inline do_tx(client interface mii_if i_mii,
                            random_generator_t &rand,
                            unsigned &burst_count, int &do_burst,
                            unsigned &len_index, unsigned &burst_len,
                            unsigned lengths[NUM_PACKET_LENGTHS],
                            unsigned data[(ETHERNET_MAX_PACKET_SIZE+3)/4])
{
  if (burst_count == 0) {
    // Configure another burst
    do_burst = (random_get_random_number(rand) & 0xff) > 200;
    len_index = random_get_random_number(rand) & (NUM_PACKET_LENGTHS - 1);
    burst_len = 1;
    if (do_burst) {
      burst_len = random_get_random_number(rand) & 0xf;
    }
    burst_count = burst_len;
  }

  int length = lengths[len_index];

  // Send a valid length in the ether len/type field
  ((char*)data)[12] = (length - HEADER_BYTES) >> 8;
  ((char*)data)[13] = (length - HEADER_BYTES) & 0xff;

  unsafe {
    i_mii.send_packet((int*)data, length);
  }

  if (burst_count) {
    burst_count--;
  }
}

void test_rx(client interface mii_if i_mii,
             client control_if ctrl)
{
  // Send a burst of frames to test the TX performance of the MAC layer and buffering
  // Just repeat the same frame numerous times to eliminate the frame setup time

  unsigned tx_data[(ETHERNET_MAX_PACKET_SIZE+3)/4];
  unsigned tx_lengths[NUM_PACKET_LENGTHS];

  // Choose random packet lengths:
  //  - there must at least be a header in order not to crash this application
  //  - there must also be 46 bytes of payload to produce valid minimum sized
  //    frames
  const int min_data_bytes = HEADER_BYTES + 46;
  random_generator_t rand = random_create_generator_from_seed(SEED);
  for (int i = 0; i < NUM_PACKET_LENGTHS; i++) {
    int do_small_packet = (random_get_random_number(rand) & 0xff) > 50;
    if (do_small_packet)
      tx_lengths[i] = random_get_random_number(rand) % (100 - min_data_bytes);
    else
      tx_lengths[i] = random_get_random_number(rand) % (ETHERNET_MAX_PACKET_SIZE - min_data_bytes);

    tx_lengths[i] += min_data_bytes;
  }

  // src/dst MAC addresses
  size_t j = 0;
  for (; j < 12; j++)
    ((char*)tx_data)[j] = j;

  // Populate the packet with known data
  int x = 0;
  const int step = 10;
  for (j = j/4; j < (ETHERNET_MAX_PACKET_SIZE+3)/4; j++) {
    x += step;
    tx_data[j] = x;
  }

  unsigned num_rx_bytes = 0;
  unsigned num_rx_packets = 0;

  int tx_do_burst = 0;
  unsigned tx_len_index = 0;
  unsigned tx_burst_len = 0;
  unsigned tx_burst_count = 0;
  int tx_packet_in_flight = 0;

  mii_info_t mii_info = i_mii.init();

  unsafe {
    int done = 0;
    while (!done) {
      #pragma ordered
      select {
        case mii_incoming_packet(mii_info):
          int * unsafe rx_data = NULL;
          do {
            int nbytes;
            unsigned timestamp;
            {rx_data, nbytes, timestamp} = i_mii.get_incoming_packet();
            if (rx_data) {
              num_rx_bytes += nbytes;
              num_rx_packets += 1;
              i_mii.release_packet(rx_data);
            }
          } while (rx_data != NULL);
          break;

      case ctrl.status_changed():
        status_t status;
        ctrl.get_status(status);
        if (status == STATUS_DONE)
          done = 1;
        break;

      case tx_packet_in_flight => mii_packet_sent(mii_info):
        tx_packet_in_flight = 0;
        break;

      default:
        break;
      }

      if (!tx_packet_in_flight) {
        do_tx(i_mii, rand, tx_burst_count, tx_do_burst,
              tx_len_index, tx_burst_len, tx_lengths, tx_data);
        tx_packet_in_flight = 1;
      }
    }

    debug_printf("Received %d packets, %d bytes\n", num_rx_packets, num_rx_bytes);

    // If there is an outstanding packet then complete it
    if (tx_packet_in_flight) {
      mii_packet_sent(mii_info);
    }

    while (1) {
      // Continue sending while Waiting for the test to be terminated by testbench
      do_tx(i_mii, rand, tx_burst_count, tx_do_burst,
            tx_len_index, tx_burst_len, tx_lengths, tx_data);
      mii_packet_sent(mii_info);
    }
  }
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
