# Bootstrap

## Flux

### Install Flux

```sh
kubectl apply --server-side --kustomize ./kubernetes/bootstrap/flux
```

### Apply Cluster Configuration

_These cannot be applied with `kubectl` in the regular fashion due to be encrypted with sops_

```sh
sops --decrypt kubernetes/bootstrap/flux/age-key.sops.yaml | kubectl apply -f -
sops --decrypt kubernetes/flux/vars/cluster-secrets.sops.yaml | kubectl apply -f -
kubectl apply -f kubernetes/flux/vars/cluster-settings.yaml
op signin
kubectl create secret generic onepassword-connect-secret -n kube-system \
--from-literal=1password-credentials.json="$(op read op://2mq4lqi5lyw6c4yghls5nilcti/1p-kubernetes-credentials-file/1password-credentials.json | base64)" \
 --from-literal=token="$(op read op://2mq4lqi5lyw6c4yghls5nilcti/1p-kubernetes-access-token/credential)"

```

### Kick off Flux applying this repository

```sh
kubectl apply --server-side --kustomize ./kubernetes/flux/config
```
