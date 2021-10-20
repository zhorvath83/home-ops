**🔹  Kubernetes upgrade preparation**

Pluto is a utility to help find deprecated Kubernetes apiVersions in code repositories and helm releases before upgrading Kubernetes verion.

Finding the places where you have deployed a deprecated apiVersion can be challenging. This is where pluto comes in. You can use pluto to check a couple different places where you might have placed a deprecated version:

📍 Infrastructure-as-Code repos: Pluto can check both static manifests and Helm charts for deprecated apiVersions

📍 Live Helm releases: Pluto can check both Helm 2 and Helm 3 releases running in your cluster for deprecated apiVersions

**📣 Installation**
https://pluto.docs.fairwinds.com/installation/#homebrew-tap

**👉  Usage**

https://pluto.docs.fairwinds.com/quickstart/#file-detection-in-a-directory
