// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#define NUM_PACKET_LENGTHS 64

void test_tx(client ethernet_tx_if tx, streaming chanend ? c_tx_hp)
{
  // Send a burst of frames to test the TX performance of the MAC layer and buffering
  // Just repeat the same frame numerous times to eliminate the frame setup time

  char data[ETHERNET_MAX_PACKET_SIZE];
  int lengths[NUM_PACKET_LENGTHS];

  const int header_bytes = 14;

  // Choose random packet lengths:
  //  - there must at least be a header in order not to crash this application
  //  - there must also be 46 bytes of payload to produce valid minimum sized
  //    frames
  const int min_data_bytes = header_bytes + 46;
  random_generator_t rand = random_create_generator_from_seed(SEED);
  for (int i = 0; i < NUM_PACKET_LENGTHS; i++) {
    int do_small_packet = (random_get_random_number(rand) & 0xff) > 50;
    if (do_small_packet)
      lengths[i] = random_get_random_number(rand) % (100 - min_data_bytes);
    else
      lengths[i] = random_get_random_number(rand) % (ETHERNET_MAX_PACKET_SIZE - min_data_bytes);

    lengths[i] += min_data_bytes;
  }

  // src/dst MAC addresses
  size_t j = 0;
  for (; j < 12; j++)
    data[j] = j;

  // Populate the packet with known data
  int x = 0;
  const int step = 10;
  for (; j < ETHERNET_MAX_PACKET_SIZE; j++) {
    x += step;
    data[j] = x;
  }

  while (1) {
    int do_burst = (random_get_random_number(rand) & 0xff) > 200;
    int len_index = random_get_random_number(rand) & (NUM_PACKET_LENGTHS - 1);
    int burst_len = 1;

    if (do_burst) {
      burst_len = random_get_random_number(rand) & 0xf;
    }

    for (int i = 0; i < burst_len; i++) {
      int length = lengths[len_index];

      // Send a valid length in the ether len/type field
      data[12] = (length - header_bytes) >> 8;
      data[13] = (length - header_bytes) & 0xff;

      if (isnull(c_tx_hp)) {
        tx.send_packet(data, length, ETHERNET_ALL_INTERFACES);
      }
      else {
        ethernet_send_hp_packet(c_tx_hp, data, length, ETHERNET_ALL_INTERFACES);
      }
    }
  }
}

void test_rx(client ethernet_cfg_if cfg,
             streaming chanend c_rx_hp,
             client control_if ctrl)
{
  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;
  cfg.add_macaddr_filter(0, 1, macaddr_filter);

  int num_bytes = 0;
  int num_packets = 0;
  int done = 0;
  unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
  while (!done) {
    ethernet_packet_info_t packet_info;

    #pragma ordered
    select {
    case ethernet_receive_hp_packet(c_rx_hp, rxbuf, packet_info):
      num_bytes += packet_info.len;
      num_packets += 1;
      break;

    case ctrl.status_changed():
      status_t status;
      ctrl.get_status(status);
      if (status == STATUS_DONE)
        done = 1;
      break;
    }
  }
  debug_printf("Received %d packets, %d bytes\n", num_packets, num_bytes);
  while (1) {
    // Wait for the test to be terminated by testbench
  }
}

#define NUM_CFG_IF 1
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  streaming chan c_rx_hp;
  streaming chan c_tx_hp;
  control_if i_ctrl[NUM_CFG_IF];

  streaming chan c_rgmii_cfg;

  par {
    on tile[1]: rgmii_ethernet_mac(i_rx_lp, NUM_RX_LP_IF,
                                   i_tx_lp, NUM_TX_LP_IF,
                                   c_rx_hp, c_tx_hp,
                                   c_rgmii_cfg,
                                   rgmii_ports,
                                   ETHERNET_DISABLE_SHAPER);

    on tile[1]: rgmii_ethernet_mac_config(i_cfg, NUM_CFG_IF, c_rgmii_cfg);

    on tile[0]: test_tx(i_tx_lp[0], c_tx_hp);
    on tile[0]: test_rx(i_cfg[0], c_rx_hp, i_ctrl[0]);

    on tile[0]: control(p_test_ctrl, i_ctrl, NUM_CFG_IF, NUM_CFG_IF);
  }
  return 0;
}
