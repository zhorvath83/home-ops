## Networking

- Configure static IP address on hosts at `/etc/network/interfaces`

- Configure DNS on your nodes at `/etc/resolv.conf` to use your router's IP and it's **not pointing to a local adblocker DNS**.

- Remove any search domains from your hosts `/etc/resolv.conf`. Search domains have an issue with alpine based containers and DNS might not resolve in them.

- Do not disable ipv6, keep it enabled even if you aren't using it. Some applications will complain about ipv6 being disabled and logs will be spammed.

- Ensure you are using `iptables` in `nf_tables` mode.

- Enable packet forwarding on the hosts, and apply other sysctl tweaks:

```sh
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding = 1
fs.inotify.max_user_watches=65536
EOF
sudo sysctl --system
```

- Make sure your nodes hostname appears in `/etc/hosts`, for example:

```sh
127.0.0.1 localhost
127.0.1.1 k8s-0
```

## System

- For a trade-off in speed over security, disable `AppArmor` and `Mitigations` on Debian/Ubuntu:

```sh
# /etc/default/grub
GRUB_CMDLINE_LINUX="apparmor=0 mitigations=off"
```

and then reconfigure grub and reboot:

```sh
sudo update-grub
sudo reboot
```

- Setup `unattended-upgrade` for use with {{ links.external('kured') }} to automatically patch and reboot your nodes.

- Disable swap
