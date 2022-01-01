
In case of `Reconciler error Helm upgrade failed: another operation (install/upgrade/rollback) is in progress`

helm history <HelmReleaseName> -n <HelmReleaseNameSpace>

helm rollback <HelmReleaseName> <RevisionNr> -n <HelmReleaseNameSpace>

flux reconcile helmrelease <HelmReleaseName> -n <HelmReleaseNameSpace>
