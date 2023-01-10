#!/bin/sh

# Place it to /jffs/addons/YazFi.d/userscripts.d
iptables --insert YazFiFORWARD --in-interface wl0.1 --out-interface br0 --destination 192.168.1.51 --proto tcp --dport 1883 -j ACCEPT
