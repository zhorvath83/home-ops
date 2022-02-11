
**🔹  Longhorn disaster recovery**

📍 Delete existing PVs and PVCs

1.)Wait for all pods to recreate / recover before continuing...

2.)Scale down your deployments using PVCs to zero
    note: Wait for pods to scale down before continuing...
    `kubectl scale deployment <deployment> --replicas=0 -n <namespace>`

3.)Delete your PVCs (as they will be empty)
    `kubectl delete pvc <pvc-name> -n <namespace>`

4.)Verify PVs and PVCs are deleted
    `kubectl get pv; kubectl get pvc -A`


📍 Restore PVCs using Longhorn web ui.

1.)Open Dashboard -> Backup
2.)Select pvc to recover and click Create Disaster Recovery Volume
3.)Make sure to select correct Access Mode: ReadWriteOnce or ReadWriteMany, Click OK.
4.)Goto -> Volume in top bar and select name to recover
5.)under Operation click Activate Disaster recovery volume
6.)Frontend: Block Device (default)
7.)Click OK
8.)Wait for volume to be Detached
9.)select volume again and under Operation click Create PV/PVC
10.)Enable both Create PVC [v] and Use Previous PVC [v]
11.)Select correct filesystem EXT4 or XFS
12.)Click OK
13.)Wait for PVC to be bound...


📍 Verification

1.)Verify PVs and PVCs are created
    `kubectl get pv; kubectl get pvc -A`

2.)Scale up your deployment again
    `kubectl scale deployment <deployment> --replicas=<number> -n <namespace>`

3.)Verify pods are up and running
    `kubectl get all -n <namespace>`
