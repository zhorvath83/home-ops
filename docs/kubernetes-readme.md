# Kubernetes cheatsheet

```bash
sudo kubectl cluster-info
sudo kubectl get nodes
kubectl get pods --all-namespaces

sudo kubectl get pod POD_NAME
sudo kubectl describe pod POD_NAME

kubectl get events --all-namespaces  --sort-by='.metadata.creationTimestamp'
kubectl logs POD_NAME -c INITCONTAINER_NAME --timestamps=true

kubectl exec --stdin --tty POD_NAME -n NAMESPACE -- /bin/ash

kubectl delete pods POD_NAME --grace-period=0 --force -n NAMESPACE
```
