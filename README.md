<div align="center">

<img src="https://camo.githubusercontent.com/5b298bf6b0596795602bd771c5bddbb963e83e0f/68747470733a2f2f692e696d6775722e636f6d2f7031527a586a512e706e67" align="center" width="144px" height="144px"/>

### My Kubernetes (Rancher k3s) cluster

_managed by Flux CD (GitOps) and Renovate_

</div>

<br/>

<div align="center">

[![Kubernetes](https://img.shields.io/badge/v1.27-blue?logo=kubernetes&logoColor=white)](https://k3s.io/)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)
[![Renovate status](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://github.com/zhorvath83/home-ops/issues/631)
[![Lines of code](https://img.shields.io/tokei/lines/github/zhorvath83/home-ops?color=brightgreen&label=lines&logo=codefactor&logoColor=white)](https://github.com/zhorvath83/home-ops/graphs/contributors)

</div>

---

## :book:&nbsp; Overview

This is my personal Kubernetes cluster. [Flux CD](https://github.com/fluxcd/flux2) watches this Git repository and makes the changes to my cluster based on the manifests in the [kubernetes](./kubernetes/) directory. [Renovate](https://github.com/renovatebot/renovate) also watches this Git repository and creates pull requests when it finds updates to Docker images, Helm charts and other dependencies.
