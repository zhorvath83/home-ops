
In case of `Reconciler error Helm upgrade failed: another operation (install/upgrade/rollback) is in progress`

helm history <HelmReleaseName> -n <HelmReleaseNameSpace>

helm history <HelmReleaseName> <Revision> -n <HelmReleaseNameSpace>

flux reconcile HelmRelease <HelmReleaseName> -n <HelmReleaseNameSpace>
