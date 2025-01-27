from scapy.all import *
import threading


def send_l2_pkts(intf):
    ethertype = 0x2222
    num_packets = 200
    pl_1500 = "a"*1500
    frame = Ether(dst="01:02:03:04:05:06", src="dc:a6:32:ca:e0:20", type=ethertype)/Raw(load=pl_1500)
    hp_frame = Ether(dst="02:03:04:05:06:07", src="dc:a6:32:ca:e0:20", type=ethertype)/Raw(load=pl_1500)
    frames = []
    frames.append(hp_frame)
    for i in range(num_packets):
        frames.append(frame)
    sendp(frames, iface=intf, verbose=False)

packet_count = 0
def sniff_pkt(intf):
    def packet_callback(packet):
        global packet_count
        if Ether in packet and packet[Ether].dst == "dc:a6:32:ca:e0:20":
            packet_count += 1
            payload = packet[Raw].load
            print("Received ", packet.summary(), len(payload), "packet ", packet_count)  # Print a summary of each packet
            #print(f"Destination MAC: {packet[Ether].dst}")
    sniff(iface=intf, prn=packet_callback, store=0, timeout=10)


if __name__ == "__main__":
    thread_send = threading.Thread(target=send_l2_pkts, args=["en7"])
    thread_sniff = threading.Thread(target=sniff_pkt, args=["en7"])

    thread_sniff.start()
    thread_send.start()
    thread_send.join()

    #send_l2_pkts("en7")
