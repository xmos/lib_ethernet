from scapy.all import *


def send_l2_pkts(intf):
    ethertype = 0x2222
    num_packets = 100
    pl_1500 = "a"*1500
    frame = Ether(dst="02:03:04:05:06:07", src="dc:a6:32:ca:e0:20", type=ethertype)/Raw(load=pl_1500) 
    frames = []
    for i in range(num_packets):
        frames.append(frame)
    sendp(frames, iface=intf, verbose=False)



if __name__ == "__main__":
    send_l2_pkts("en7")
