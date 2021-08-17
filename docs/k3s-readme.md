**🔹  Rancher K3s**

📍 Manual install at first node:
`sudo curl -sfL https://get.k3s.io | sh -s - server --cluster-init --disable=traefik,servicelb,local-storage --kubelet-arg=image-gc-high-threshold=70 --kubelet-arg=image-gc-low-threshold=50`

`sudo cat /var/lib/rancher/k3s/server/node-token`

📍 Other servers in the cluster:
`sudo curl -sfL https://get.k3s.io | sh -s - server --server https://<IP>:6443 --disable=traefik,servicelb,local-storage --kubelet-arg=image-gc-high-threshold=70 --kubelet-arg=image-gc-low-threshold=50 --token <TOKEN>`

📍 Manual K3s upgrade:
`sudo curl -sfL https://get.k3s.io | sh -s - server --server https://<IP>:6443 --disable=traefik,servicelb,local-storage --kubelet-arg=image-gc-high-threshold=70 --kubelet-arg=image-gc-low-threshold=50`


📍 To see what container images have been pulled locally: `sudo k3s crictl image`

📍 To delete any images no currently used by a running container: `sudo k3s crictl rmi --prune`

**📣  Kubernetes image garbage collection DOCs:**
https://kubernetes.io/docs/concepts/architecture/garbage-collection/#containers-images
