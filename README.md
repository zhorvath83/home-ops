# My Kubernetes (Rancher k3s) cluster

![Kubernetes Logo](https://raw.githubusercontent.com/zhorvath83/home-ops/d611d50a6b6c9cc2b38a11c6bd577704f833b63d/docs/src/assets/kubernetes-logo.png)

*managed by Flux CD (GitOps) and Renovate*

[![Kubernetes](https://img.shields.io/badge/v1.27-blue?logo=kubernetes&logoColor=white)](https://k3s.io/)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)
[![Renovate status](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://github.com/zhorvath83/home-ops/issues/631)
[![Lines of code](https://img.shields.io/tokei/lines/github/zhorvath83/home-ops?color=brightgreen&label=lines&logo=codefactor&logoColor=white)](https://github.com/zhorvath83/home-ops/graphs/contributors)

---

## 📖 Overview

This is my personal Kubernetes cluster. [Flux CD](https://github.com/fluxcd/flux2) 
watches this Git repository and makes the changes to my cluster based on the 
manifests in the [kubernetes](./kubernetes/) directory. 
[Renovate](https://github.com/renovatebot/renovate) also watches this Git repository 
and creates pull requests when it finds updates to Docker images, Helm charts and 
other dependencies.
