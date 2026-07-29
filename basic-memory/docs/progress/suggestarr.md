---
title: suggestarr
type: progress
permalink: home-ops/docs/progress/suggestarr
topic: SuggestArr — AI media recommender that auto-requests Jellyseerr content from
  Plex watch history
status: done
priority: low
scope: Deploy SuggestArr (ciuse99/suggestarr) as a self-hosted recommender that pulls
  recently-watched history from Plex, finds similar titles via TMDB (optionally AI-ranked
  via an OpenAI-compatible LLM), and files download requests into the existing Jellyseerr
  (seerr) instance. Web UI for config, cron jobs, and logs; config PVC backed by VolSync/Kopia;
  internal-only exposure.
rationale: The Plex + full Arr + Jellyseerr + Trakt stack already automates acquisition
  but not discovery. SuggestArr closes the discovery loop with minimal new surface
  area by reusing the existing Plex token, Jellyseerr, and Trakt wiring; AI ranking
  is optional and provider-pluggable so it can land with no new infrastructure first.
options:
- 'Namespace: media (alongside plex-trakt-sync, another Plex automation sidecar) —
  recommended; alternative downloads alongside seerr'
- 'Exposure: envoy-internal only (LAN, k8s-gateway split DNS) like the Arr stack —
  recommended; alternative envoy-external behind the gateway-oidc OIDC gate'
- 'LLM provider: reuse Mistral (consistent with paperless-gpt, no new infra) — recommended;
  alternatives Ollama local (new component, node CPU/GPU), OpenRouter, or AI disabled
  (TMDB-only similarity)'
- 'Database: embedded SQLite on the config PVC (simplest, VolSync-backed) — recommended;
  alternative external PostgreSQL/MySQL'
related_areas:
- k8s-workloads
- networking
- external-secrets
- observability
---

# SuggestArr — AI media recommender that auto-requests Jellyseerr content from Plex watch history

## Metadata (observation-form, schema validation)

- [topic] SuggestArr — AI media recommender that auto-requests Jellyseerr content from Plex watch history
- [status] done
- [priority] low

## Scope

- [observation] Deploy SuggestArr (`ciuse99/suggestarr`, MIT, ~1.2k★) as a self-hosted recommender sidecar to the existing Plex-based media stack.
- [observation] Watch-history source: Plex (`plex.media.svc.cluster.local:32400`), reusing the existing 1Password `plex` item / `PLEX_TOKEN` already consumed by `plex-trakt-sync`.
- [observation] Request sink: Jellyseerr (`seerr` in `downloads` namespace, `reqs.${PUBLIC_DOMAIN}`) via its API key.
- [observation] Similarity lookup via TMDB API key; optional AI ranking through any OpenAI-compatible LLM endpoint (Mistral / Ollama / OpenRouter / LiteLLM / Gemini).
- [observation] Optional per-user Trakt history as additional seed (project already runs `plex-trakt-sync`).
- [observation] Web UI on container port 5000 for config, cron scheduling, real-time logs, and config validation.
- [observation] Config persisted on a VolSync/Kopia-backed PVC; embedded SQLite by default.
- [observation] Internal-only exposure (`envoy-internal`, LAN via k8s-gateway split DNS) — admin/config tool, not end-user facing.

## Rationale

- [observation] The Plex + Arr + Jellyseerr + Trakt stack automates acquisition but not discovery; SuggestArr closes the discovery loop with the least new surface area.
- [observation] Reuses existing platform wiring (Plex token, Jellyseerr, Trakt, External Secrets, VolSync, app-template HelmRelease shape) — no new platform component required for the TMDB-only path.
- [observation] AI ranking is optional and provider-pluggable, so the item can land in a no-new-infra form first and gain an LLM later without rework.

## Open decisions (options)

- [option] Namespace — `media` (alongside `plex-trakt-sync`, another Plex automation sidecar) recommended; alternative `downloads` alongside `seerr`.
- [option] Exposure — `envoy-internal` only (consistent with the Arr stack) recommended; alternative `envoy-external` behind the gateway-oidc OIDC gate (`components/gateway-oidc`) if remote admin access is wanted.
- [option] LLM provider — reuse Mistral (consistent with `paperless-gpt`, no new infra) recommended; alternatives Ollama local (new component, node CPU/GPU cost), OpenRouter, or AI disabled (TMDB-only similarity) for a zero-dependency first cut.
- [option] Database — embedded SQLite on the config PVC (simplest, VolSync-backed) recommended; alternative external PostgreSQL/MySQL.

## Implementation notes

- [step] Follow the canonical app-template HelmRelease shape (radarr as reference): `chartRef: app-template` OCIRepository, `interval: 30m`, values-only `spec`, hardened `securityContext` (runAsNonRoot, UID/GID 10001, drop ALL, readOnlyRootFilesystem), `defaultPodOptions` (automountServiceAccountToken false, enableServiceLinks false).
- [step] `ks.yaml`: `components: [volsync]`, `dependsOn` on `onepassword-connect/external-secrets` (NFS not required for SuggestArr config, so omit `democratic-csi` unless a media mount is added later); `targetNamespace: media`; `postBuild.substitute.APP: suggestarr` + small `VOLSYNC_CAPACITY` (e.g. 1Gi).
- [step] ExternalSecret `suggestarr` → `suggestarr-secret` from a new 1Password item `suggestarr`: TMDB API key, Jellyseerr API key, Plex token (or reference the shared `plex` item), and LLM provider key + base URL + model only if AI is enabled.
- [step] Route: `envoy-internal` parentRef, hostname `suggestarr.${PUBLIC_DOMAIN}`, Homepage annotations (group `Media`).
- [step] Pin image tag with `@sha256:` digest and add a `# renovate:` annotation for `ciuse99/suggestarr` so Renovate tracks it.
- [gap] SuggestArr ships no official Helm chart — wrap the container directly in app-template (the repo-native pattern used by `isponsorblocktv`/`subsyncarr` for non-chart images); no chart vendoring needed.
- [gap] Confirm SuggestArr runs as non-root UID 10001 with `readOnlyRootFilesystem: true`; its config volume likely needs a writable data path — adjust persistence accordingly, as done for other stateful apps.

## Dependencies

- [observation] Reuses `plex` (media), `seerr` (downloads), optionally `plex-trakt-sync` (Trakt seeds) — all already deployed.
- [observation] Platform prerequisites: `onepassword-connect`/external-secrets, `envoy-gateway`/`k8s-gateway` (internal DNS), `volsync`/Kopia (config backup). No new platform component required for the TMDB-only path.

## Related

- relates_to [[k8s-workloads]]
- relates_to [[networking]]
- relates_to [[external-secrets]]
- relates_to [[observability]]


## Execution (done, 2026-07-30)

Deployed SuggestArr as a hardened app-template HelmRelease in the `media` namespace, LAN-only behind the envoy-oidc gate. Direct commits to `main` (repo norm; Flux watches `refs/heads/main`).

### Built
- [step] `kubernetes/apps/media/suggestarr/ks.yaml` + `app/helmrelease.yaml` — Flux KS (`components: [volsync, gateway-oidc]`, `targetNamespace: media`, UID/GID 1000/1001, VolSync 1Gi config PVC); app-template HR, image `ciuse99/suggestarr:v2.10.1` (renovate-tracked, digest-pinned), port 5000, rootless (runAsNonRoot, drop ALL, readOnlyRootFilesystem, seccomp RuntimeDefault), `SUGGESTARR_AUTH_DISABLED: "true"`, AD-023 labels, envoy-internal route, Homepage annotations (Media group).
- [step] `kubernetes/apps/downloads/seerr/app/ciliumnetworkpolicy.yaml` — ingress CNP admitting the suggestarr consumer (media ns) on Seerr API port 5055, so SuggestArr pushes approved requests over `http://seerr.downloads.svc.cluster.local:5055` (in-cluster, bypassing the OIDC gate).

### Decisions / deviations from spec
- [decision] Exposure: `envoy-internal` + `gateway-oidc` SSO gate (Pocket IdP, `media_users`) — combines the roadmap's recommended internal exposure with its alternative OIDC-gate option. SuggestArr has no native OIDC (INSTALLATION.md), so envoy-oidc is the SSO path.
- [decision] Auth: `SUGGESTARR_AUTH_DISABLED: "true"` — the gate is the single auth path, no SuggestArr user. Safe via the Cilium `allow-gateway-internal` label (gateway is the only pod ingress).
- [decision] LLM: Gemini (user choice), but SuggestArr reads LLM config only from config.yaml + DB (`api_service/config/config.py`), never from env — the Gemini key is entered in web UI Settings > Advanced; no ExternalSecret/envFrom.
- [decision] Non-root UID/GID 1000/1001 (rwlove reference), not the spec's 10001. Namespace `media` (matches recommendation).

### Cornerstone requirement (manual approval)
- [observation] No automatic/question-less downloads: web UI Settings > Advanced → "Approve requests before sending them to Seer" (global) + per-job "Pause while Seer requests are pending" (Jobs page). Both web-UI toggles; activate on first-run.

### Open follow-up
- [observation] `just pocket-id apply` (human, local-exec LAN-only admin API) to create the `suggestarr` Pocket ID client + sync `suggestarr_client_secret` into `HomeOps/pocket-id-clients`. Until then the gateway-oidc companion ExternalSecret is `SecretSyncedError` (expected transient).

### Related
- decision_link [[AD-023-cnp-threat-model-audit]]
