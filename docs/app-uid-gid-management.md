# Centralized UID/GID Management (APP_UID / APP_GID)

## Overview

Every application's UID/GID is defined **once** in the Flux Kustomization (`ks.yaml`)
`postBuild.substitute` block. HelmReleases, VolSync movers, and PUID/PGID environment
variables all reference these centralized values via Flux envsubst — eliminating
hardcoded numeric IDs from HelmReleases and preventing UID/GID mismatches between
the application and its backup mover.

## Architecture

### Data flow

```
ks.yaml                          helmrelease.yaml              replicationsource.yaml
postBuild.substitute:            securityContext:               moverSecurityContext:
  APP_UID: "10001"   ──envsubst──>  runAsUser: ${APP_UID}        runAsUser: ${APP_UID:=10001}
  APP_GID: "10001"   ──envsubst──>  runAsGroup: ${APP_GID}       runAsGroup: ${APP_GID:=10001}
                                    fsGroup: ${APP_GID}          fsGroup: ${APP_GID:=10001}
```

### How Flux envsubst works

Flux Kustomization's `postBuild.substitute` performs simple environment variable
substitution on **all** rendered YAML within the Kustomization's `path` — including
resources pulled in via Kustomize `components`. This means:

- Variables defined in the `ks.yaml` are available in the HelmRelease (in `path`)
- Variables are also available in VolSync component templates (pulled via `components`)
- Variables work even in Kustomizations **without** the VolSync component
- The VolSync `replicationsource.yaml` uses `${APP_UID:=10001}` syntax (default value)

### What `APP_UID` represents

`APP_UID` / `APP_GID` represents the **file ownership UID/GID** — the user that
owns persistent data on disk. This semantic is important because:

- The VolSync restic mover must run as the same user who owns the files
- A UID mismatch between app and mover causes backup/restore permission errors
- For most apps, the file owner = the `securityContext.runAsUser`
- For root-startup apps (linuxserver.io images), the file owner = the `PUID`/`PGID`

## Patterns

### Standard rootless application (most common)

The app runs as a non-root user. `APP_UID` matches `securityContext.runAsUser`.

**ks.yaml:**
```yaml
spec:
  postBuild:
    substitute:
      APP: sonarr
      APP_UID: "10001"
      APP_GID: "10001"
```

**helmrelease.yaml:**
```yaml
defaultPodOptions:
  securityContext:
    runAsNonRoot: true
    runAsUser: ${APP_UID}
    runAsGroup: ${APP_GID}
    fsGroup: ${APP_GID}
    fsGroupChangePolicy: OnRootMismatch
    seccompProfile:
      type: RuntimeDefault
```

**Examples:** sonarr, radarr, bazarr, prowlarr, plex, maintainerr, actual, mealie,
homepage, home-gallery, echo, cloudflare-tunnel, speedtest-exporter, pocket-id,
tinyauth, system-upgrade-controller, paperless-gpt, plex-trakt-sync, qbittorrent

### Non-default UID application

Some apps require a specific non-default UID (e.g., upstream image expectation).

**ks.yaml:**
```yaml
spec:
  postBuild:
    substitute:
      APP: paperless
      APP_UID: "1000"
      APP_GID: "1000"
```

**helmrelease.yaml** — same pattern as standard, `${APP_UID}` resolves to `1000`.

**Examples:** paperless (1000:1000), seerr (1000:1000), subsyncarr (1000:1000)

### Root-startup with PUID/PGID (linuxserver.io-style images)

The container starts as root, then an internal entrypoint switches to the user
specified by `PUID`/`PGID`. The `securityContext.runAsUser` stays hardcoded at `0`
(required for startup), but `APP_UID` reflects the actual file owner.

**ks.yaml:**
```yaml
spec:
  postBuild:
    substitute:
      APP: wallos
      APP_UID: "1000"     # ← file owner (PUID), NOT the securityContext user
      APP_GID: "1000"     # ← file group (PGID)
```

**helmrelease.yaml:**
```yaml
defaultPodOptions:
  securityContext:
    runAsNonRoot: false
    runAsUser: 0          # ← stays hardcoded, root required for startup
    runAsGroup: 0
    fsGroup: 0
# ...
env:
  PUID: ${APP_UID}        # ← references the file owner UID
  PGID: ${APP_GID}        # ← references the file owner GID
```

**Examples:** wallos (APP_UID=1000, secCtx=0), calibre-web-automated (APP_UID=1000,
APP_GID=100, secCtx commented out)

### Root application with root file ownership

The app runs as root AND files are owned by root. Both `APP_UID` and
`securityContext.runAsUser` are `0`.

**ks.yaml:**
```yaml
spec:
  postBuild:
    substitute:
      APP_UID: "0"
      APP_GID: "0"
```

**Examples:** resticprofile/app, resticprofile/gui (backrest)

### Upstream-specific UID

Some upstream Helm charts or images mandate a specific UID. Use the upstream value.

**Examples:** onepassword-connect (999:999), flux-provider-pushover (65532:65532)

## Complete application reference

| Application | APP_UID | APP_GID | securityContext | PUID/PGID | VolSync |
|---|---|---|---|---|---|
| actual | 10001 | 10001 | `${APP_UID}` | — | yes |
| bazarr | 10001 | 10001 | `${APP_UID}` | — | yes |
| calibre-web-automated | 1000 | 100 | commented out | `${APP_UID}`/`${APP_GID}` | yes |
| cloudflare-tunnel | 10001 | 10001 | `${APP_UID}` | — | no |
| echo | 10001 | 10001 | `${APP_UID}` | — | no |
| flux-provider-pushover | 65532 | 65532 | `${APP_UID}` | — | no |
| home-gallery | 10001 | 10001 | `${APP_UID}` | — | no |
| homepage | 10001 | 10001 | `${APP_UID}` | — | no |
| maintainerr | 10001 | 10001 | `${APP_UID}` | — | yes |
| mealie | 10001 | 10001 | `${APP_UID}` | `${APP_UID}`/`${APP_GID}` | yes |
| onepassword-connect | 999 | 999 | `${APP_UID}` | — | no |
| paperless | 1000 | 1000 | `${APP_UID}` | — | yes |
| paperless-gpt | 10001 | 10001 | `${APP_UID}` | — | yes |
| plex | 10001 | 10001 | `${APP_UID}` | — | yes |
| plex-trakt-sync | 10001 | 10001 | `${APP_UID}` | — | yes |
| pocket-id | 10001 | 10001 | `${APP_UID}` | — | yes |
| prowlarr | 10001 | 10001 | `${APP_UID}` | — | yes |
| qbittorrent | 10001 | 10001 | `${APP_UID}` | — | yes |
| qbt-upgrade-p2pblocklist | 10001 | 10001 | `${APP_UID}` | — | no |

| radarr | 10001 | 10001 | `${APP_UID}` | — | yes |
| resticprofile/app | 0 | 0 | `${APP_UID}` | — | no |
| resticprofile/gui (backrest) | 0 | 0 | `${APP_UID}` | — | yes |
| seerr | 1000 | 1000 | `${APP_UID}` | — | yes |
| sonarr | 10001 | 10001 | `${APP_UID}` | — | yes |
| speedtest-exporter | 10001 | 10001 | `${APP_UID}` | — | no |
| subsyncarr | 1000 | 1000 | `${APP_UID}` | `${APP_UID}`/`${APP_GID}` | no |
| system-upgrade-controller | 10001 | 10001 | `${APP_UID}` | — | no |
| tinyauth | 10001 | 10001 | `${APP_UID}` | — | yes |
| wallos | 1000 | 1000 | hardcoded `0` | `${APP_UID}`/`${APP_GID}` | yes |

## Adding a new application

1. **Define variables in `ks.yaml`:**
   Add `APP_UID` and `APP_GID` to `postBuild.substitute`. Use `"10001"` unless
   the image requires a different UID.

2. **Reference in HelmRelease:**
   Use `${APP_UID}` for `runAsUser`, `${APP_GID}` for `runAsGroup` and `fsGroup`.
   Never hardcode numeric UIDs in the HelmRelease (exception: root-startup apps
   where `runAsUser: 0` must stay hardcoded).

3. **PUID/PGID env vars:**
   If the image uses PUID/PGID (linuxserver.io-style), set them to
   `${APP_UID}` / `${APP_GID}`.

4. **VolSync:**
   If the app uses the VolSync component, the `replicationsource.yaml` template
   automatically picks up `APP_UID`/`APP_GID` from the same `postBuild.substitute`.
   No extra configuration needed.

5. **Verify consistency:**
   After deployment, check that the file ownership on the PVC matches `APP_UID:APP_GID`:
   ```bash
   kubectl exec -n <namespace> <pod> -- ls -la /config
   ```

## Rules and constraints

- **Single source of truth:** UID/GID values live ONLY in `ks.yaml`. HelmReleases
  MUST use `${APP_UID}`/`${APP_GID}` variable references.

- **No hardcoded UIDs in HelmReleases** — with one exception: root-startup apps
  that require `runAsUser: 0` for container startup keep this hardcoded.

- **APP_UID = file owner, not necessarily runAsUser:** For root-startup apps, the
  pod's `securityContext.runAsUser` may be `0`, but `APP_UID` reflects who owns the
  files (the PUID value). The VolSync mover needs the file owner UID.

- **Quoted strings in ks.yaml:** Always quote the values (`APP_UID: "10001"`, not
  `APP_UID: 10001`). Flux envsubst works with strings; unquoted integers may cause
  YAML type issues.

- **Default fallback in VolSync component:** The `replicationsource.yaml` uses
  `${APP_UID:=10001}` syntax. If `APP_UID` is not defined in the ks.yaml, it falls
  back to `10001`. This default exists for backwards compatibility but should not be
  relied upon — always define `APP_UID` explicitly.

## Related files

- VolSync component: `kubernetes/components/volsync/replicationsource.yaml`
- Cluster settings: `kubernetes/flux/vars/cluster-settings.yaml`
- Per-app ks.yaml: `kubernetes/apps/{namespace}/{app}/ks.yaml`
- Per-app HR: `kubernetes/apps/{namespace}/{app}/app/helmrelease.yaml`
