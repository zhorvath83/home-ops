# Creating an HTPasswd file

Make sure you’ve got an htpasswd file available before you tackle the Kubernetes configuration. You can create a new single user htpasswd in your terminal:

`apt install apache2-utils`
`htpasswd -c auth example-user`

You’ll be prompted to enter the password. A new file called auth will be created in your working directory.

Next you need to base64-encode your credentials string so it can be used as a value in a Kubernetes secret:

`cat auth | base64`

Copy the base64-encoded string to your clipboard. We’ll use it in the next section to create a Kubernetes secret containing your credentials.

# Adding a Kubernetes Secret

NGINX Ingress references htpasswd files as Kubernetes secrets. The file’s content must be stored in the auth key of an Opaque secret. Kubernetes also has a built-in basic-auth secret type but this isn’t suitable for NGINX Ingress.

## Create a new secret manifest and apply it to your cluster with Kubectl:

apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: htpasswd
data:
  auth: <base64-encoded htpasswd file>
