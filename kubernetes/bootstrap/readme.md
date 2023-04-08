# Bootstrap

## Flux

### Install Flux

```sh
kubectl apply --server-side --kustomize ./kubernetes/bootstrap/flux
```

### Apply Cluster Configuration


```sh
op signin

kubectl create secret generic sops-age -n flux-system \
--from-literal=age.agekey="$(op read op://HomeOps/homelab-age-key/keys.txt)"

kubectl create secret generic onepassword-connect-secret -n kube-system \
--from-literal=1password-credentials.json="$(op read op://HomeOps/1p-kubernetes-credentials-file/1password-credentials.json | base64)" \
 --from-literal=token="$(op read op://HomeOps/1p-kubernetes-access-token/credential)"

sops --decrypt kubernetes/flux/vars/cluster-secrets.sops.yaml | kubectl apply -f -

kubectl apply -f kubernetes/flux/vars/cluster-settings.yaml

```

### Kick off Flux applying this repository

```sh
kubectl apply --server-side --kustomize ./kubernetes/flux/config
```
