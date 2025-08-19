# Helm Troubleshooting

In case of `Reconciler error Helm upgrade failed: another operation (install/upgrade/rollback) is in progress`

```bash
helm history HELM_RELEASE_NAME -n HELM_RELEASE_NAMESPACE

helm rollback HELM_RELEASE_NAME REVISION_NR -n HELM_RELEASE_NAMESPACE

flux reconcile helmrelease HELM_RELEASE_NAME -n HELM_RELEASE_NAMESPACE
```

## Resolving issues with HelmReleases that are failed

<https://support.d2iq.com/hc/en-us/articles/8295311458964-Resolving-issues-with-HelmReleases-that-are-failed>
