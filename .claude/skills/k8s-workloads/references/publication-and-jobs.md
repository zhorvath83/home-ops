# Publication And Jobs

Use this reference for routes, Homepage metadata, media-app decisions, and scheduled jobs.

## External Publication

Default external publication uses the established Gateway API pattern:

- hostname under `${PUBLIC_DOMAIN}`
- `parentRefs` targeting `envoy-external` in namespace `networking`
- backend pointing to the app service identifier

When the app should also be directly reachable from the LAN, attach the same route to `envoy-internal` as well. Leave technical or internet-only endpoints on `envoy-external` only.

Do not copy old Traefik comments into new work unless the live manifests still depend on them.

If the change requires listener, certificate, tunnel, or ExternalDNS work, switch to `networking-platform`.

## Homepage

For user-facing apps that should appear on the dashboard, inspect sibling annotations and keep the same group and icon conventions.

Common fields include:

- `gethomepage.dev/enabled: "true"`
- `gethomepage.dev/name`
- `gethomepage.dev/group`
- `gethomepage.dev/icon`

## Auth

There is no shared auth platform declared under `kubernetes/apps/`.

- prefer app-native auth or OIDC when the target app supports it well
- inspect sibling apps before inventing an auth dependency

## Media App Questions

For media-oriented apps, inspect `plex`, `calibre-web-automated`, `maintainerr`, and `home-gallery` before designing the workload.

Answer these questions explicitly:

- only Gateway exposure, or also LAN-oriented service exposure
- hardware transcoding, or only software and transient transcode space
- which NFS paths are read-only vs read-write
- whether cache should be isolated from the backed-up config PVC

## CronJobs

The repo uses bjw-s `app-template` with `type: cronjob`, not raw Kubernetes CronJob manifests, when a scheduled job belongs to an app.

Rules:

- keep the job in a sibling directory such as `backup/` when that fits the existing app pattern
- use `concurrencyPolicy: Forbid`
- reuse the main image and security context when practical
- disable service exposure and probes for the job
- mount only the volumes the job actually needs
