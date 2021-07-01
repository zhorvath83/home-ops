**🔹  GitOps with Flux**

📍 Here we will be installing flux after some quick bootstrap steps.

1.)Verify Flux can be installed
`flux check --pre`

2.)Pre-create the flux-system namespace
`kubectl create namespace flux-system`

3.)Add the Flux GPG key in-order for Flux to decrypt SOPS secrets
```
export KEY_FP=...
gpg --export-secret-keys --armor "${KEY_FP}" |
sudo kubectl create secret generic sops-gpg \
--namespace=flux-system \
--from-file=sops.asc=/dev/stdin
```

4.)Pull repo source

5.)Install Flux
`kubectl apply --kustomize=./cluster/base/flux-system`



**📣  Post installation**

📍  Verify Flux
`kubectl --kubeconfig=./kubeconfig get pods -n flux-system`


📍 [VSCode SOPS extension](https://marketplace.visualstudio.com/items?itemName=signageos.signageos-vscode-sops)
VSCode SOPS is a neat little plugin for those using VSCode. It will automatically decrypt you SOPS secrets when you click on the file in the editor and encrypt them when you save and exit the file.

**👉  Debugging**

📍 Manually sync Flux with your Git repository
`flux reconcile source git flux-system`

📍 Show the health of you kustomizations
`kubectl get kustomization -A`

📍 Manually reconcile kustomization
`flux reconcile kustomization apps`

📍 Show the health of your main Flux GitRepository
`flux get sources git`

📍 Show the health of your HelmReleases
`flux get helmrelease -A`

📍 Show the health of your HelmRepositorys
`flux get sources helm -A`

📍 Reconcile flux resources
`flux reconcile helmrelease traefik -n traefik`

📍 Print the reconciliation logs of all Flux custom resources in your cluster
`flux logs --all-namespaces`

📍 Stream logs for a particular log level
`flux logs --follow --level=error --all-namespaces`

📍 Filter logs by kind, name and namespace
`flux logs --kind=Kustomization --name=podinfo --namespace=default`

📍 Print logs when Flux is installed in a different namespace than flux-system
`flux logs --flux-namespace=my-namespace`
