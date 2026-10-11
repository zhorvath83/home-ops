---
title: local-ai-stack
type: progress_note
permalink: home-ops/docs/progress/local-ai-stack
---

# local-ai-stack — execution progress

## Metadata (observation-form)

- [topic] MVP wave of the local-ai-stack roadmap: ai namespace, llama-cpp + open-webui
- [status] IN PROGRESS — code committed and pushed (PR #4510, branch feat/local-ai-stack); NOT merged, NOT live
- [branch] feat/local-ai-stack
- [implements] [[local-ai-stack]] roadmap, Plan steps 1-3 (step 4 bake-off runs after merge)
- [created] 2026-10-11

## Decisions taken at implementation (owner, 2026-10-11)

- [decision] Open WebUI auth: native OAuth against Pocket ID (no gateway-oidc), PKCE S256, OAuth config env-authoritative (ENABLE_OAUTH_PERSISTENT_CONFIG=false)
- [decision] Access group: infra_admins (both allowed and admin role)
- [decision] Hostnames: chat.${PUBLIC_DOMAIN} (open-webui), llm.${PUBLIC_DOMAIN} (llama-cpp API), both envoy-internal only
- [decision] Model download: plain curl init container against pinned HF revisions with sha256 verification (no python/uv, no PyPI egress); models listed in app/config/models.conf
- [decision] Per-consumer llama.cpp API keys (LLAMA_API_KEY is a comma list): open_webui_api_key, metrics_api_key in 1Password HomeOps/llama-cpp
- [decision] Thinking disabled via LLAMA_ARG_REASONING=off (generic switch, works for both candidates)

## Measured baseline (2026-10-11)

- [observation] CPU: Intel Core i7-10700T, 8 cores / 16 threads, AVX2+FMA (no AVX-512) — threads=6
- [observation] Node ephemeral/local storage: ~860 GiB available of 1 TB — 50Gi model PVC is no concern

## Done

- [done] Commits 109b907d8 (renovate regex versioning for server-b<build>) and cd251c543 (ai stack), pushed, PR #4510
- [done] 1Password items HomeOps/llama-cpp and HomeOps/open-webui created with random 64-hex values
- [done] Validation: kustomize build (3 trees), helm template of both charts, pre-commit, just pocket-id lint — all green

## Blocked
- [resolved] 2026-10-11: the Pocket ID provisioning API key had expired (HTTP 401); owner rotated it in HomeOps/pocket-id. terraform plan showed exactly 1 add (pocketid_client open-webui), applied; sync-secrets wrote open-webui_client_secret (run through `script -q /dev/null` so op gets a pty — avoids the piped-stdin gotcha); `just pocket-id audit` reports all 25 clients group-restricted.

## Next

- [next] Rotate Pocket ID API key -> just pocket-id apply (no piped stdin) -> merge PR #4510
- [next] Live verification: download init (~39 GB), /health, /v1/models with key, Prometheus target up, Grafana dashboard, Open WebUI login via Pocket ID + chat round-trip
- [next] Verify on live: open-webui readOnlyRootFilesystem + STATIC_DIR emptyDir; envoy streamIdleTimeout 5m vs long CPU prefill
- [next] Bake-off gate (roadmap Plan step 4); switch model by editing --model/--alias in the HelmRelease

## Relations

- implements [[local-ai-stack]]
