from scapy.all import *
import threading
from mii_packet import MiiPacket
import random
import copy


def send_l2_pkts(intf, packets):
    # Convert to scapy Ether frames
    frames = []
    for i in range(num_packets + 1):
        byte_data = bytes(packets[i].data_bytes)
        frame = Ether(dst=packets[i].dst_mac_addr_str, src=packets[i].src_mac_addr_str, type=packets[i].ether_len_type)/Raw(load=byte_data)
        frames.append(frame)

    # Send over ethernet!
    sendp(frames, iface=intf, verbose=False)

packet_count = 0
def sniff_pkt(intf, expected_packets):
    def packet_callback(packet, expect_packets):
        global packet_count
        if Ether in packet and packet[Ether].dst == expect_packets[0].dst_mac_addr_str:
            payload = packet[Raw].load
            expected_payload = bytes(expect_packets[packet_count].data_bytes)
            if payload != expected_payload:
                print("ERROR: mismatch in pkt number {packet_count}")
                print(f"Received: {payload}")
                print(f"Expected: {expected_payload}")
                assert(False)
            #print("Received ", packet.summary(), len(payload), "packet ", packet_count)  # Print a summary of each packet
            packet_count += 1

    sniff(iface=intf, prn=lambda pkt: packet_callback(pkt, expected_packets), timeout=10)

    print(f"Received {packet_count} looped back packets")


if __name__ == "__main__":
    seed = 0
    rand = random.Random()
    rand.seed(seed)

    ethertype = 0x2222
    num_packets = 200
    src_mac_address = [0xdc, 0xa6, 0x32, 0xca, 0xe0, 0x20]

    loop_back_packets = []
    packets = []
    mac_address = [0x02, 0x03, 0x04, 0x05, 0x06, 0x07] # Send one HP packet
    packets.append(MiiPacket(rand,
        dst_mac_addr=mac_address,
        src_mac_addr=src_mac_address,
        ether_len_type = ethertype,
        create_data_args=['step', (1, 46, 0)]
        ))

    # Send remaining LP packets
    mac_address = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06]
    for i in range(num_packets):
        packets.append(MiiPacket(rand,
            dst_mac_addr=mac_address,
            src_mac_addr=src_mac_address,
            ether_len_type = ethertype,
            create_data_args=['step', (1, 1500, 0)]
            ))
        packet = copy.deepcopy(packets[-1])
        tmp = packet.dst_mac_addr
        packet.dst_mac_addr = packet.src_mac_addr
        packet.src_mac_addr = tmp
        loop_back_packets.append(packet)

    thread_send = threading.Thread(target=send_l2_pkts, args=["en7", packets])
    thread_sniff = threading.Thread(target=sniff_pkt, args=["en7", loop_back_packets])

    thread_sniff.start()
    thread_send.start()
    thread_send.join()

    #send_l2_pkts("en7")
