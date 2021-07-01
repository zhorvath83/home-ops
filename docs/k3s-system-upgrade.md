**Upgrade k3s kubernetes cluster with a system upgrade controller**

It is advisable to track the security vulnarabilities published by Rancher Labs around k3s. For example, in November 2020 a critical bug was detected in k3s. Therefore, it is quite important to be able to update k3s without interupting the k3s cluster, hence this procedure from Rancher Labs.

```bash
$ kubectl get nodes
NAME   STATUS   ROLES    AGE    VERSION
n3     Ready    <none>   117d   v1.19.2+k3s1
n2     Ready    <none>   117d   v1.19.2+k3s1
n4     Ready    <none>   117d   v1.19.2+k3s1
n1     Ready    master   117d   v1.19.2+k3s1
n5     Ready    <none>   117d   v1.19.2+k3s1
```

## Making a k3s upgrade plan

We need to decide to which k3s version we need to upgrade, therefore, check out the [GitHub release page of k3s](https://github.com/rancher/k3s/releases). The latest release of this writing was v1.19.4+k3s1 (30 November 2020).

The upgrade plan will upgrade the k3s server node (called k3s-server in the plan) and the k3s worker nodes (called k3s-agent in the plan). For that reason we must first label our master node (in our case *n1*) if that was not yet done:

```bash
$ kubectl get node --selector='node-role.kubernetes.io/master'
NAME   STATUS   ROLES    AGE    VERSION
n1     Ready    master   117d   v1.19.2+k3s1
```

Here we see that node *n1* was already labelled 'master', however, if that was not yet the case we could realize this by:

```bash
kubectl label node n1 node-role.kubernetes.io/master=true
```

And, for the magic to happen we just have to enable to k3s upgrade with command:

```bash
$ kubectl label node --all k3s-upgrade=enabled
node/n2 labeled
node/n4 labeled
node/n3 labeled
node/n1 labeled
node/n5 labeled
```

We believe it is better to disable the k3s upgrades once it is done with the command:

```bash
$ kubectl label node --all --overwrite k3s-upgrade=disabled
node/n5 labeled
node/n1 labeled
node/n2 labeled
node/n4 labeled
node/n3 labeled
```

To start the k3s version upgrade overwrite the label k3s-upgrade again with keyword *enabled*.
