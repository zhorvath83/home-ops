<div align="center">

<img src="https://camo.githubusercontent.com/5b298bf6b0596795602bd771c5bddbb963e83e0f/68747470733a2f2f692e696d6775722e636f6d2f7031527a586a512e706e67" align="center" width="144px" height="144px"/>

### My Kubernetes (Rancher k3s) cluster

_managed by Flux CD (GitOps) and Renovate_

</div>

<br/>

<div align="center">

[![k3s](https://img.shields.io/badge/k3s-v1.23.4-brightgreen?style=for-the-badge&logo=kubernetes&logoColor=white)](https://k3s.io/)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white&style=for-the-badge)](https://github.com/pre-commit/pre-commit)
[![GitHub Workflow Status](https://img.shields.io/github/workflow/status/zhorvath83/kube-cluster/Schedule%20-%20Renovate?label=renovate&logo=renovatebot&style=for-the-badge)](https://github.com/zhorvath83/kube-cluster/actions/workflows/schedule-renovate.yaml)
[![Lines of code](https://img.shields.io/tokei/lines/github/zhorvath83/kube-cluster?style=for-the-badge&color=brightgreen&label=lines&logo=codefactor&logoColor=white)](https://github.com/zhorvath83/kube-cluster/graphs/contributors)

</div>

---

## :book:&nbsp; Overview

This is my personal Kubernetes cluster. [Flux CD](https://github.com/fluxcd/flux2) watches this Git repository and makes the changes to my cluster based on the manifests in the [cluster](./cluster/) directory. [Renovate](https://github.com/renovatebot/renovate) also watches this Git repository and creates pull requests when it finds updates to Docker images, Helm charts, and other dependencies.
