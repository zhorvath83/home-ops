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
