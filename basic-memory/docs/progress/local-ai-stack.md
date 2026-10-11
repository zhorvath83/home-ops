---
title: local-ai-stack
type: progress_note
permalink: home-ops/docs/progress/local-ai-stack
---

# local-ai-stack — execution progress

## Metadata (observation-form)

- [topic] MVP wave of the local-ai-stack roadmap: ai namespace, llama-cpp + open-webui
- [status] LIVE — PR #4510 squash-merged to main (25478acee) + follow-ups 1fb0b3981, ecb3eca4b; MVP wave deployed and verified 2026-10-11; bake-off gate (Plan step 4) still open
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

## Live verification (2026-10-11)

- [verified] Downloads: both GGUFs sha256 OK (Qwen3.6 20.82 GiB at ~65 MB/s); restarts skip via .verified markers
- [verified] llama-cpp: /health 200 without key; /v1/models and /metrics 401 without key; /v1/models with key -> [qwen3.6-35b-a3b]; n_slots=2, n_ctx_slot=16384 (kv_unified=false); pod memory ~20.3 GiB resident
- [verified] open-webui -> llama-cpp path (CNP + per-consumer key) answers Hungarian prompts; reasoning_content empty (thinking off works)
- [verified] Prometheus target up{job=llama-cpp}=1, llamacpp:* metrics present; GrafanaFolder ai + GrafanaDashboard llama-server synchronized
- [verified] Open WebUI: runs with readOnlyRootFilesystem (STATIC_DIR emptyDir), offline embedding model loads from the bundled cache, /api/config shows only the Pocket ID provider, login redirect carries PKCE S256; owner confirmed working login
- [measured] Qwen3.6 UD-Q4_K_XL, threads=6: generation 6.3-6.6 tok/s, prompt processing 13-18 tok/s on short prompts — BELOW the >=10 tok/s gate. Quality spot-check: summary fluent and correct; spelling-fix final sentence correct but the explanation contained wrong claims
- [fixed] CNP: HF resolve redirects to us.aws.cdn.hf.co; single-label *.hf.co was POLICY_DENIED (Hubble) -> **.hf.co / **.huggingface.co (Cilium 1.20)
- [fixed] CORS_ALLOW_ORIGIN restricted to the chat origin (startup warned on '*')
- [gotcha] First rollout outlives the injected 10m HelmRelease timeout and the Deployment's 600s progressDeadline -> HR InstallFailed, then Deployment stuck Progressing=False (kstatus Failed, rollback impossible). Recovery: kubectl rollout restart deploy/llama-cpp + flux reconcile hr --force. One-off per fresh PVC; recurs only if a new model is added to models.conf

## Next
- [next] Throughput below gate: try LLAMA_ARG_THREADS 8 (all physical cores) and measure decode + node health; then Gemma 4 26B-A4B under the same flags (switch --model/--alias)
- [next] Bake-off gate (roadmap Plan step 4): Hungarian prompt set, paperless set, sure tool-calling round, TTFT on an 8k prompt
- [next] Consider progressDeadlineSeconds on the llama-cpp controller if new models are added later

## Relations

- implements [[local-ai-stack]]
