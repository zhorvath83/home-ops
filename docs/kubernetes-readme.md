**🔹  Kubernetes cheatsheat**

sudo kubectl cluster-info
sudo kubectl get nodes
kubectl get pods --all-namespaces

sudo kubectl get pod <pod>
sudo kubectl describe pod <pod>

kubectl get events --all-namespaces  --sort-by='.metadata.creationTimestamp'
kubectl logs <pod> -c <initcontainer-name> --timestamps=true

kubectl exec --stdin --tty nameOfPosd -n <nameSpace>  -- /bin/ash

kubectl delete pods <pod> --grace-period=0 --force -n <nameSpace>
