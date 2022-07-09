**🔹  Modifying Longhorn replica's count**

git clone https://github.com/longhorn/longhorn && cd longorn

LONGHORN_NEW_REPLICAS=1

# Upgrade the Longhorn Helm Chart
helm upgrade longhorn ./chart --namespace longhorn-system \
    --set persistence.defaultClassReplicaCount="$LONGHORN_NEW_REPLICAS" \
    --set csi.attacherReplicaCount="$LONGHORN_NEW_REPLICAS" \
    --set csi.provisionerReplicaCount="$LONGHORN_NEW_REPLICAS" \
    --set csi.resizerReplicaCount="$LONGHORN_NEW_REPLICAS" \
    --set csi.snapshotterReplicaCount="$LONGHORN_NEW_REPLICAS" \
    --set defaultSettings.defaultReplicaCount="$LONGHORN_NEW_REPLICAS"

# Attaching longhorn volume to Host
- Go to Longhorn UI, attach the volume to node-x
- SSH into node-x. Run `ls -l /dev/longhorn`. You will see the block device with the name "VOLUME-NAME"
- Mount the block device to a directory on the node-x by: `sudo mount /dev/longhorn/<VOLUME-NAME> /mnt/longhornvolume`
- Now you can access the data at /mnt/longhornvolume. Try `ls /mnt/longhornvolume`

# CLI tool to easily migrate Kubernetes persistent volumes
https://github.com/utkuozdemir/pv-migrate
