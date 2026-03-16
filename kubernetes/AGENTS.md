# Kubernetes Agent Guide

This guide applies to everything under `kubernetes/`.

## What Lives Here

`kubernetes/` contains the declarative cluster state reconciled by Flux. The main structure is:

- `apps/`: application and platform workloads grouped by namespace or domain
- `bootstrap/`: initial Flux bootstrap resources
- `components/`: reusable Kustomize components
- `flux/`: Flux configuration, repositories, and cluster variables

## Subtree Guides

Use more specific guides when working in these areas:

- networking platform: [apps/networking/AGENTS.md](apps/networking/AGENTS.md)
- security and auth: [apps/security/AGENTS.md](apps/security/AGENTS.md)
- external secrets platform: [apps/external-secrets/AGENTS.md](apps/external-secrets/AGENTS.md)

## Traversal Rule

For any work under `kubernetes/`, apply guides in this order:

1. [../AGENTS.md](../AGENTS.md)
2. [AGENTS.md](AGENTS.md)
3. the nearest subtree `AGENTS.md`, if one exists for the target path

Examples:

- `kubernetes/apps/default/...` -> root guide + kubernetes guide
- `kubernetes/apps/networking/...` -> root guide + kubernetes guide + networking guide
- `kubernetes/apps/security/...` -> root guide + kubernetes guide + security guide

## Primary Goal

When adding or changing workloads here, optimize for:

- low resource usage on a single-node cluster
- rootless and hardened execution by default
- GitOps-safe declarative changes
- reuse of established repo patterns before introducing new ones

## Workload Guardrails

When adding or changing Kubernetes workloads:

- prefer `runAsNonRoot`, `allowPrivilegeEscalation: false`, dropped capabilities, and `readOnlyRootFilesystem: true` when the image supports them
- prefer explicit CPU and memory requests, and prefer memory limits without CPU limits unless a workload has a specific need for CPU throttling
- do not add `privileged`, `hostNetwork`, `hostPID`, or fixed root execution unless the live sibling patterns or upstream image requirements justify it
- when an app needs an exception such as root execution, a writable root filesystem, or privileged access, keep the exception narrowly scoped and preserve any nearby comment that explains why

## Authoritative Patterns

- Flux `Kustomization` objects in `ks.yaml` are the entry points for deployable app units.
- App manifests usually live under an `app/` directory referenced by `ks.yaml`.
- Shared reusable logic belongs in `components/` only when it is already proven across multiple apps.
- Dependencies between apps must be declared in `spec.dependsOn`; do not rely on creation order.
- Prefer official Helm charts first, then bjw-s `app-template`, then custom manifests only when needed.

## GitOps Apply Boundary

Treat everything under `kubernetes/` as desired state for Flux, not as an imperative apply tree.

- Local edits in this repository do not change the cluster by themselves.
- `flux reconcile` does not apply the local working tree. It only tells Flux to refresh the configured Git source and reconcile the committed state that Flux can fetch.
- If changes are uncommitted or not pushed to the Git source watched by Flux, a reconcile will not deploy them.
- After local Kubernetes edits, first decide which state you are talking about: local-only, committed, pushed, or live in cluster. State that explicitly in user updates and final responses.
- Only suggest or run `task fx:reconcile` or `flux reconcile ...` when it will help with committed GitOps state, not as a substitute for commit/push.
- If the user wants to verify or apply uncommitted changes against the cluster, call out that this would require a non-GitOps imperative step and confirm that this is intentionally outside the normal repo workflow.

## YAML Authoring Rules

When editing Kubernetes YAML in this repo:

- start files with `---`
- use 2-space indentation
- include `yaml-language-server` schema comments when the live sibling files already do so or when a stable schema URL is known
- keep top-level key order conventional: `apiVersion`, `kind`, `metadata`, then `spec` or `data`
- prefer short, stable anchors only when the same value is reused several times in one manifest
- do not use YAML anchors for scalar app names, resource names, or `controllers` keys; write those explicitly to avoid misleading structure reuse
- keep formatting close to neighboring files instead of reformatting entire manifests

## Namespace Conventions

Common live namespaces and their intent:

- `default`: user-facing applications
- `networking`: ingress, DNS, and edge plumbing
- `security`: auth and security-facing services
- `observability`: metrics and dashboards
- `external-secrets`: secret delivery platform
- `kube-system`: cluster infrastructure components
- `cert-manager`: certificate management
- `flux-system`: GitOps control plane
- `system-upgrade`: K3s upgrade controller

## New App Skeleton

For a standard new application under `kubernetes/apps/<group>/<app>/`, start from this shape:

```text
kubernetes/apps/<group>/<app>/
├── ks.yaml
└── app/
    ├── kustomization.yaml
    ├── ocirepository.yaml
    ├── helmrelease.yaml
    ├── externalsecret.yaml      # only if app-level secrets are needed
    ├── secret.sops.yaml         # only if repo-encrypted secret data is needed
    └── config/                  # only for non-secret static config files
```

Rules:

- `ks.yaml` is the Flux entry point.
- `app/kustomization.yaml` lists only resources physically present in `app/`.
- Do not add app-local `pvc.yaml` or `volsync.yaml` for normal VolSync-backed apps; those come from `spec.components`.
- Keep names lowercase and hyphenated.
- Flux Kustomization names follow `cluster-apps-<app>`.

This skeleton is mainly for user-facing or standard app deployments. Platform areas such as `networking/`, `security/`, `external-secrets/`, and `observability/` often have deliberate deviations; inspect sibling trees before copying a default-app pattern into those areas.

## OCIRepository Rules

Every HelmRelease needs a corresponding `ocirepository.yaml` in the same directory.

Template:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/source.toolkit.fluxcd.io/ocirepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: <app>
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: <chart-version>
  url: oci://<registry-url>
```

Critical rules:

- do NOT add `namespace` in OCIRepository metadata — Flux inherits it from the parent Kustomization
- do NOT add `namespace` in the HelmRelease `chartRef` block
- OCIRepository `name` must match the HelmRelease `metadata.name`
- always use `interval: 15m` for OCIRepository (HelmRelease uses `interval: 30m`)
- for bjw-s app-template: `url: oci://ghcr.io/bjw-s-labs/helm/app-template`

## Active Platform Conventions

- Gateway API with Envoy Gateway is the active ingress model.
- External exposure should use `HTTPRoute` resources targeting `envoy-external` unless the existing area clearly uses another pattern.
- External Secrets with the `onepassword` store is the standard for app-managed secrets.
- Persistent app backups use the Flux `components:` hook with `../../../../components/volsync` where that pattern already exists.
- Storage typically uses `democratic-csi-local-hostpath` for PVC-backed apps and direct NFS mounts for selected media workloads.

## Kustomization Conventions

Typical `ks.yaml` shape:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-apps-<app>
  namespace: flux-system
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: <app>
  dependsOn:
    - name: cluster-apps-onepassword-store
    - name: cluster-apps-democratic-csi
  path: ./kubernetes/apps/<group>/<app>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: home-ops-kubernetes
  interval: 1h
  targetNamespace: <namespace>
  timeout: 5m
  wait: false
  components:
    - ../../../../components/volsync
  postBuild:
    substitute:
      APP: <app>
```

Defaults visible in the live repo:

- `interval: 1h`
- `timeout: 5m`
- `wait: false`
- `prune: true`
- `sourceRef.name: home-ops-kubernetes`

## Dependency Rules

Use these heuristics when writing `dependsOn`:

- PVC-backed app: add `cluster-apps-democratic-csi`
- External Secrets using 1Password: add `cluster-apps-onepassword-store`
- App talks to another in-cluster dependency during startup: add that app's Flux Kustomization
- Child or sidecar app under same feature group: depend on the parent app when startup order matters

Examples already present:

- `paperless-gpt` depends on `cluster-apps-paperless`
- most user apps with app secrets and PVCs depend on both store and CSI

Do not assume this area is perfectly clean; verify sibling apps before copying a pattern.

Platform exceptions to remember:

- some infrastructure trees split one logical subsystem into multiple Flux Kustomizations, for example `envoy-gateway-certificate`, `envoy-gateway`, and `envoy-gateway-config`
- some apps depend on observability or operator layers rather than storage, for example Grafana depends on `cluster-apps-kube-prometheus-stack`

## App Kustomization Conventions

Typical `app/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: <namespace>
resources:
  - ./ocirepository.yaml
  - ./helmrelease.yaml
  - ./externalsecret.yaml
  - ./secret.sops.yaml
labels:
  - pairs:
      app.kubernetes.io/name: <app>
```

Ordering:

1. `ocirepository.yaml`
2. `externalsecret.yaml` if present
3. `secret.sops.yaml` if present
4. `helmrelease.yaml`
5. extra resources after that

## Editing Rules

- Before changing an app, inspect its `ks.yaml`, `app/kustomization.yaml`, and main manifest set together.
- Match the namespace and dependency conventions already used by sibling apps in the same domain.
- Keep `postBuild.substitute` values as the single source of truth for app-specific VolSync variables when that pattern is present.
- Do not reintroduce app-local `volsync.yaml` or duplicate PVC templates where the shared component already covers the case.
- Treat commented Traefik remnants as migration leftovers unless the live manifests still depend on them.
- When reporting progress after edits, do not imply the cluster has changed unless the committed Git source has been updated and Flux has reconciled it successfully.

## HelmRelease Baseline

For bjw-s `app-template` workloads, the common baseline is:

- `interval: 30m`
- `install.createNamespace: true`
- `install.remediation.retries: -1`
- `upgrade.cleanupOnFail: true`
- `upgrade.remediation.strategy: rollback`
- `upgrade.remediation.retries: 3`
- `uninstall.keepHistory: false`

Use that baseline unless an existing sibling app clearly differs for a good reason.

## Security Context Rules

Default security model:

- pod-level `runAsNonRoot: true`
- `runAsUser`, `runAsGroup`, `fsGroup` aligned
- `fsGroupChangePolicy: OnRootMismatch`
- `seccompProfile.type: RuntimeDefault`
- container-level `allowPrivilegeEscalation: false`
- container-level `readOnlyRootFilesystem: true`
- container capabilities dropped
- writable paths added explicitly through `emptyDir` or PVC mounts

Typical pod-level shape:

```yaml
defaultPodOptions:
  automountServiceAccountToken: false
  enableServiceLinks: false
  securityContext:
    runAsNonRoot: true
    runAsUser: ${APP_UID}
    runAsGroup: ${APP_GID}
    fsGroup: ${APP_GID}
    fsGroupChangePolicy: OnRootMismatch
    seccompProfile:
      type: RuntimeDefault
```

Typical container-level shape:

```yaml
securityContext:
  privileged: false
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

Exceptions are allowed only when the live behavior proves they are required. Document the reason inline next to the exception, as seen in `wallos`.

## APP_UID And APP_GID

Treat `APP_UID` and `APP_GID` as the single source of truth for file ownership when the app uses VolSync or PUID/PGID-style images.

Rules:

- define them in `ks.yaml` `postBuild.substitute`
- reuse them in pod security context
- reuse them in app env vars like `PUID` and `PGID` when needed
- let the VolSync component inherit them for mover ownership
- do not hardcode numeric IDs in multiple places if `postBuild` can provide them once

Observed patterns:

- standard rootless apps often use `10001`
- `paperless` and `seerr` use `1000`
- `wallos` runs the pod as root but file ownership is still `1000`
- root-startup apps may keep `runAsUser: 0` while still exporting file-owner IDs via env vars

## Storage Decision Rules

Choose storage intentionally:

- app config/data persisted in-cluster: existing PVC via `existingClaim: <app>`
- media libraries or shared NAS data: NFS mount using `${CONF_NFS_SRV_IP}`
- temporary writable paths for hardened containers: `emptyDir`
- second cache or special-purpose PVC: separate explicit PVC only when the shared VolSync component does not cover the need

Examples:

- `sonarr`: PVC for `/config`, NFS for `/media`, `emptyDir` for `/tmp`
- `pocket-id`: PVC for `/app/data`, `emptyDir` for `/tmp`
- `plex`: extra explicit cache PVC in addition to normal app storage

If the app should be backed up, use the VolSync component rather than inventing app-local backup manifests.

## Media App Pattern

For media-serving apps such as Jellyfin or Plex-like workloads, inspect `plex`, `calibre-web-automated`, `maintainerr`, and `home-gallery` before designing the manifest.

Common live media patterns:

- config and state on a PVC
- media libraries mounted from NFS
- temp or transcode space on `emptyDir`
- Homepage annotations under `Media` or another user-facing group
- occasionally both private route exposure and LAN-oriented service exposure are needed

Questions that must be answered explicitly for a new media app:

- does it need only Gateway exposure, or also a `LoadBalancer` service for LAN clients and discovery
- does it need hardware transcoding or just software/transient transcode space
- which NFS paths should be mounted read-only vs read-write
- should cache be isolated from the backed-up config PVC

The docs are enough to scaffold the workload, but these policy decisions still need to be made per application.

## VolSync Rules

The active backup model is the shared component at [components/volsync/replicationsource.yaml](components/volsync/replicationsource.yaml).

Default behavior inherited from the component:

- schedule: `0 2 * * *`
- prune interval: `7`
- cache: `1Gi`
- capacity: `1Gi`
- retain daily: `7`
- retain weekly: `2`
- retain monthly: `0`
- storage class and snapshot class: `democratic-csi-local-hostpath`

Scheduling policy:

- Treat backup timing as an app-level concern even though the VolSync manifests come from the shared component.
- The implementation lives in each app `ks.yaml` under `spec.postBuild.substitute.VOLSYNC_SCHEDULE`.
- Keep the shared component default as the fallback only; when multiple apps use VolSync, prefer explicit per-app schedules in `ks.yaml`.
- Reserve earlier isolated slots for the largest or most sensitive backups, then place the rest after them in 5-minute offsets.
- The current operating convention is: dedicate the first slots to the largest backups, then schedule the remaining apps sequentially in 5-minute increments rather than leaving them on the shared default.
- When adjusting schedules, inspect the whole fleet first so new entries do not accidentally collide with existing slots.

How to inspect current schedules:

- Preferred: `rg -n "VOLSYNC_SCHEDULE" kubernetes/apps -g 'ks.yaml'`
- Also works: `grep VOLSYNC_SCHEDULE kubernetes/apps/**/ks.yaml`

Common `postBuild.substitute` knobs:

- `APP` required
- `APP_UID`, `APP_GID`
- `VOLSYNC_CAPACITY`
- `VOLSYNC_CACHE`
- `VOLSYNC_SCHEDULE`
- `VOLSYNC_PRUNE_DAYS`
- `VOLSYNC_RETAIN_HOURLY`
- `VOLSYNC_RETAIN_DAILY`
- `VOLSYNC_RETAIN_WEEKLY`
- `VOLSYNC_RETAIN_MONTHLY`
- `VOLSYNC_CLAIM` for non-default PVC names

Do not create `ReplicationDestination` manifests for normal steady-state config; restores are handled through the VolSync task workflow.

## Secrets Rules

There are two main secret patterns:

- app secrets from 1Password via `ExternalSecret`
- cluster/bootstrap secrets encrypted with SOPS

For `ExternalSecret`:

- use `ClusterSecretStore` named `onepassword`
- set a deterministic target secret name
- use `creationPolicy: Owner` when the app owns the generated Secret
- prefer `dataFrom.extract` for whole-item imports when the secret structure fits
- use `template.data` when the app needs renamed or composed fields

Representative example: [apps/security/pocket-id/app/externalsecret.yaml](apps/security/pocket-id/app/externalsecret.yaml).

## Routing And Publication

Default external publication uses bjw-s `route:` with Gateway API:

- hostname under `${PUBLIC_DOMAIN}`
- `parentRefs` pointing to `envoy-external` in namespace `networking`
- backend points to the `app` service identifier

For published apps, also add Homepage annotations when the app should appear on the dashboard. Common annotations:

- `gethomepage.dev/enabled: "true"`
- `gethomepage.dev/name`
- `gethomepage.dev/group`
- `gethomepage.dev/icon`

Old Traefik comments may exist in some manifests. Do not copy them into new work unless the app still truly depends on them.

Infrastructure exceptions:

- some platform charts expose themselves without the bjw-s `route:` abstraction
- Envoy Gateway itself is configured through separate `Gateway`, policy, certificate, and NetworkPolicy manifests rather than a simple app route

## Auth Rules

Authentication strategy today:

- native OIDC against Pocket ID where the app supports it well
- TinyAuth forward auth for apps without native OIDC

Before adding auth to a new app:

- check whether the app already supports OIDC cleanly
- inspect live security apps under `apps/security/`
- inspect sibling apps in the same category for how public routes and secrets are wired

Do not assume the OIDC rollout is complete across the repo; verify the current state for the target app family.

## Resource And Health Rules

Every new app should have:

- resource requests
- at least memory limits where appropriate
- health probes appropriate for the app
- `reloader.stakater.com/auto: "true"` annotation when config or secrets are mounted

### Reloader Annotation

Add the reloader annotation on the controller level whenever the app mounts ConfigMaps or Secrets (including ExternalSecret-generated ones). Without it, config or secret changes do not trigger a pod restart, causing silent drift.

Placement:

```yaml
controllers:
  <app>:
    annotations:
      reloader.stakater.com/auto: "true"
```

### Probe Template

Use a YAML anchor to share the same spec between liveness and readiness probes. This is the standard DRY pattern across the repo:

```yaml
probes:
  liveness: &probes
    enabled: true
    custom: true
    spec:
      httpGet:
        path: /ping
        port: <port>
      initialDelaySeconds: 30
      periodSeconds: 30
      timeoutSeconds: 5
      failureThreshold: 5
  readiness: *probes
  startup:
    enabled: false
```

Adjust `path` and `port` to the app's actual health endpoint. Enable `startup` probe when boot time is long or initial readiness is noisy.

## Config File Rules

If an app needs non-secret static config files:

- store them under `app/config/`
- generate a ConfigMap or Secret in `app/kustomization.yaml`
- mount them explicitly
- use an init container only when the image requires copying files into a writable target path

Do not place secrets in `config/`.

## CronJob Pattern

CronJobs are deployed as bjw-s `app-template` HelmReleases with `type: cronjob`, not as native Kubernetes CronJob manifests.

Directory structure when a CronJob belongs to an existing app:

```text
kubernetes/apps/<group>/<app>/
├── ks.yaml              # contains both Kustomizations
├── app/                 # main application
│   ├── kustomization.yaml
│   ├── helmrelease.yaml
│   └── ...
└── backup/              # CronJob (or other scheduled task)
    ├── kustomization.yaml
    ├── ocirepository.yaml
    └── helmrelease.yaml
```

Controller shape:

```yaml
controllers:
  <app>-backup:
    type: cronjob
    cronjob:
      concurrencyPolicy: Forbid
      schedule: "30 0 * * *"
      successfulJobsHistory: 1
      failedJobsHistory: 3
    containers:
      app:
        image: *img
        command: ["/bin/sh", "-c"]
        args:
          - |
            # script content
        securityContext: *sc
        resources:
          requests:
            cpu: 10m
            memory: 256Mi
          limits:
            memory: 1Gi
```

CronJob rules:

- `concurrencyPolicy: Forbid` to prevent parallel runs
- reuse the same image as the main app via YAML anchor (`*img`)
- reuse the same security context via YAML anchor (`*sc`)
- disable service: `service.app.enabled: false`
- disable probes — not needed for CronJobs
- mount only the volumes the job actually needs

## New App Playbook

When deploying a new application, work in this order:

1. Choose the target group and inspect 2-3 sibling apps with similar exposure, storage, and auth needs.
2. Decide chart strategy: official chart first, then bjw-s `app-template`.
3. Create `ks.yaml` with correct namespace, dependencies, and `postBuild.substitute`.
4. Create `app/kustomization.yaml`.
5. Add `ocirepository.yaml`.
6. Add `helmrelease.yaml` with baseline install/upgrade policy, security context, probes, resources, service, route, and persistence.
7. Add `externalsecret.yaml` or `secret.sops.yaml` if needed.
8. Add VolSync through `spec.components` and `postBuild` variables if the app data should be backed up.
9. Add Homepage annotations if the app is user-facing.
10. Compare the result against at least one sibling app and one security/storage analogue before considering it done.

## Validation Playbook

After editing a Kubernetes app:

1. Read back `ks.yaml`, `app/kustomization.yaml`, and `helmrelease.yaml` together.
2. Check for missing dependencies with `rg` against sibling apps.
3. If secrets are involved, verify naming consistency between `ExternalSecret`, mounted Secret refs, and the app manifests.
4. If VolSync is involved, verify that `APP` and any overrides match the expected claim and repository naming.
5. Use the existing task and Flux tooling for follow-up validation when the environment is available.

Helpful repo entry points:

- [../Taskfile.yml](../Taskfile.yml)
- [../.taskfiles/Flux/Tasks.yaml](../.taskfiles/Flux/Tasks.yaml)
- [../.taskfiles/Kubernetes/Tasks.yaml](../.taskfiles/Kubernetes/Tasks.yaml)
- [../.taskfiles/VolSync/Tasks.yaml](../.taskfiles/VolSync/Tasks.yaml)

## Common Checks

- Use `rg` to find the same pattern in sibling applications before inventing a new one.
- For dependency-sensitive work, inspect nearby `ks.yaml` files in the same subtree.
- If changing routing or auth, inspect both the target app and the shared security/networking apps that support it.
- If changing backup behavior, inspect both the app `ks.yaml` and [components/volsync/replicationsource.yaml](components/volsync/replicationsource.yaml).

## Current Reality To Prefer Over Old Notes

- `pocket-id` and `tinyauth` are present and active under `apps/security/`.
- Observability is split into `kube-prometheus-stack`, standalone `grafana`, and supporting exporters.
- CrowdSec does not currently exist in the live `apps/` tree, even though it appears in memory notes.
