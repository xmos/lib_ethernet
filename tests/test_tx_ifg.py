# Copyright 2014-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import Pyxsim as px
import os
from pathlib import Path
import pytest

from mii_clock import Clock
from mii_phy import MiiReceiver
from rgmii_phy import RgmiiTransmitter
from mii_packet import MiiPacket
from helpers import get_sim_args, create_if_needed, args
from helpers import get_mii_rx_clk_phy, get_mii_tx_clk_phy, get_rgmii_rx_clk_phy, get_rgmii_tx_clk_phy
from helpers import get_rmii_clk, get_rmii_rx_phy
from helpers import generate_tests
from collections import defaultdict
from hw_helpers import log_ifg_summary


num_test_packets = (1514-60+1)*2 # 2 packets for each valid payload length. Takes about 15mins to run in sim

def start_test(phy):
    phy.num_packets = 0
    phy.num_bytes = 0
    phy.start_time = 0
    phy.ifg_full_dict = defaultdict(list) # dictionary containing IFGs seen for each payload length

def packet_checker(packet, phy):
    # The CRC is not included in the packet bytes
    num_packet_bytes = len(packet.get_packet_bytes()) + 4
    phy.num_packets += 1
    phy.num_bytes += num_packet_bytes

    if phy.num_packets > 1:
        phy.ifg_full_dict[num_packet_bytes].append(round(packet.get_ifg()/1e6, 2))


    if phy.num_packets == num_test_packets:
        print(phy.ifg_full_dict)
        log_ifg_summary(phy.ifg_full_dict,
                        ifg_summary_file="ifg_sweep_summary_sim.txt",
                        ifg_full_file="ifg_sweep_full_sim.txt"
                        )
        phy.xsi.terminate()


def do_test(mac, arch, rx_clk, rx_phy, tx_clk, tx_phy, tx_width=None):
    start_test(rx_phy)

    testname = 'test_tx_ifg'

    if tx_width:
        profile = f'{mac}_{rx_phy.get_name()}_tx{tx_width}_{arch}'
        print(f"Running {testname}: {mac} {rx_phy.get_name()} phy, {tx_width} tx_width at {rx_clk.get_name()} for {arch} arch")
    else:
        profile = f'{mac}_{rx_phy.get_name()}_{arch}'
        print(f"Running {testname}: {mac} {rx_phy.get_name()} phy at {rx_clk.get_name()} for {arch} arch")

    binary = f'{testname}/bin/{profile}/{testname}_{profile}.xe'
    assert os.path.isfile(binary)

    simargs = get_sim_args(testname, mac, rx_clk, rx_phy)

    simthreads = [rx_clk, rx_phy]
    if tx_clk != None:
        simthreads.append(tx_clk)
    if tx_phy != None:
        simthreads.append(tx_phy)

    result = px.run_on_simulator_(  binary,
                                    simthreads=simthreads,
                                    simargs=simargs,
                                    do_xe_prebuild=False,
                                    timeout=60*60)

    assert result is True, f"{result}"


test_params_file = Path(__file__).parent / "test_tx_ifg/test_params.json"
@pytest.mark.parametrize("params", generate_tests(test_params_file)[0], ids=generate_tests(test_params_file)[1])
def test_tx_ifg(capfd, params):
    with capfd.disabled():
        verbose = False
        # Test 100 MBit - MII XS2
        if params["phy"] == "mii":
            (rx_clk_25, rx_mii) = get_mii_rx_clk_phy(packet_fn=packet_checker)
            (tx_clk_25, tx_mii) = get_mii_tx_clk_phy(do_timeout=False, verbose=verbose)
            do_test(params["mac"], params["arch"], rx_clk_25, rx_mii, tx_clk_25, tx_mii)

        elif params["phy"] == "rgmii":
            # Test 100 MBit - RGMII
            if params["clk"] == "25MHz":
                (rx_clk_25, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_25MHz, packet_fn=packet_checker)
                (tx_clk_25, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_25MHz, do_timeout=False, verbose=verbose)
                do_test(params["mac"], params["arch"], rx_clk_25, rx_rgmii, tx_clk_25, tx_rgmii)
            # Test 1000 MBit - RGMII
            elif params["clk"] == "125MHz":
                (rx_clk_125, rx_rgmii) = get_rgmii_rx_clk_phy(Clock.CLK_125MHz, packet_fn=packet_checker)
                (tx_clk_125, tx_rgmii) = get_rgmii_tx_clk_phy(Clock.CLK_125MHz, do_timeout=False, verbose=verbose)
                do_test(params["mac"], params["arch"], rx_clk_125, rx_rgmii, tx_clk_125, tx_rgmii)
            else:
                assert 0, f"Invalid params: {params}"

        elif params["phy"] == "rmii":
            clk = get_rmii_clk(Clock.CLK_50MHz)
            rx_rmii_phy = get_rmii_rx_phy(params['tx_width'],
                                            clk,
                                            packet_fn=packet_checker,
                                            verbose=verbose
                                        )

            do_test(params["mac"], params["arch"], clk, rx_rmii_phy, None, None, tx_width=params['tx_width'])
        else:
            assert 0, f"Invalid params: {params}"
