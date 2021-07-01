
List all certificates that you have:
kubectl get certificate --all-namespaces


Try to figure out the problem using describe command:
kubectl describe certificate CERTIFICATE_NAME -n YOUR_NAMESPACE


The output of the above command contains the name of the associated certificate request. Dig into more details using describe command once again:
kubectl describe certificaterequest CERTTIFICATE_REQUEST_NAME -n YOUR_NAMESPACE


You may also want to troubleshoot challenges with the following command:
kubectl describe challenges --all-namespaces