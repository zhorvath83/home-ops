---
title: local-ai-stack
type: progress_note
permalink: home-ops/docs/progress/local-ai-stack
---

# local-ai-stack — execution progress

## Metadata (observation-form)

- [topic] MVP wave of the local-ai-stack roadmap: ai namespace, llama-cpp + open-webui
- [status] LIVE — MVP wave deployed 2026-10-11 (PR #4510); bake-off decided 2026-10-12: Qwen3.6 35B-A3B, no MTP, 2 slots (f2d7dd443). Open: 10 tok/s gate revision in the roadmap, real-data paperless/sure validation, Plan step 5 consumers
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

## Open WebUI prompt bloat (2026-10-11)

- [measured] 8 threads (1dca74fe5): decode 7.4 tok/s (6 threads: 6.3-6.6), prompt processing ~26-33 tok/s; still below the 10 tok/s gate
- [problem] Open WebUI v0.12 native function calling attaches builtin tool schemas to every chat: ~7.2-7.7k prompt tokens => ~4 min to first token on cold cache (worse with 2 concurrent slots)
- [gotcha] Open WebUI snapshots ALL config keys (368 rows, table config) into webui.db on first boot; afterwards the DB row wins over env, so later env changes are silently ignored. Fix 4dbb3ed06: ENABLE_PERSISTENT_CONFIG=false — env/git is authoritative on every start; admin UI changes do not survive a restart
- [fixed] 1e907687d (ENABLE_MEMORIES/NOTES/CODE_INTERPRETER/CODE_EXECUTION=false) + 0d30d3a0c (DEFAULT_MODEL_METADATA capabilities.builtin_tools=false; ef27774c2 knowledge-only variant superseded). Measured after: new chat prompt 19-38 tokens, first token ~1-2 s, decode 5.9-7.3 tok/s
- [observation] Intermediate step with only memories/notes/code off: prompt ~4.0k tokens (time, ask_user, chats tools + their instructions remained)

## Bake-off (2026-10-12)

Suite: tools/llm-bakeoff/bakeoff.py (runs in the open-webui pod with its own key; synthetic data only): 3x decode on a short prompt (cache_prompt=false), one ~9k-token prompt, 10 Hungarian prompts, 3 paperless-style extractions (JSON + correspondent + date), 12 sure-style categorisations, one tool-calling round. Same flags for all: 8 threads, ctx 32768, temperature 0.2, reasoning off.

| Variant | Decode short | Decode HU avg | ~9k prompt | Paperless / Sure / Tool |
|---|---|---|---|---|
| Qwen3.6 35B-A3B UD-Q4_K_XL (PTQ) | 7.2-7.8 tok/s | 8.1 | 251 s (36 tok/s) | 3/3 · 11/12 · ok |
| Qwen3.6 MTP GGUF + draft-mtp (n_max 2, 1 slot) | 6.8-7.2 | 7.7 | 263 s | 3/3 · 11/12 · ok |
| Gemma 4 26B-A4B UD-Q4_K_M (PTQ) | 7.2-7.3 | 7.4 | 322 s (28 tok/s) | 3/3 · 11/12 · ok |
| Gemma 4 26B-A4B QAT UD-Q4_K_XL + MTP drafter (n_max 4, 1 slot) | 3.7-4.2 | 7.4 | 296 s | 3/3 · 11/12 · ok |

- [decision] Owner decision 2026-10-12: Qwen3.6 35B-A3B without MTP, 2 slots. Rationale: fastest decode and prefill (prefill ~28% ahead of Gemma, which matters for paperless documents), equal accuracy on the consumer-shaped tasks, single-answer instruction following suits structured output
- [decision] The served file is the Qwen3.6 MTP GGUF (unsloth/Qwen3.6-35B-A3B-MTP-GGUF @5bc3e238) used WITHOUT speculative decoding — avoids a re-download; re-check after the switch: 2 slots load, decode 7.6-7.8 tok/s
- [measured] MTP speculative decoding is a net loss on this CPU: Qwen draft acceptance ~0.9-1.0 (mean len ~3) yet decode got slower; Gemma QAT drafter acceptance only 0.39 and decode halved. MTP also limits the server to one slot (-np > 1 unsupported per the Unsloth card). Hypothesis, unverified: MoE verification reads different experts per drafted token, so memory bandwidth is not saved
- [measured] The 10 tok/s gate is not reachable with this model class on an i7-10700T (DDR4 dual channel): every variant decodes at ~7-8 tok/s. The gate needs revising in the roadmap (owner decision pending)
- [observation] Accuracy on consumer-shaped tasks was identical across all four variants: paperless 3/3 valid JSON with correct correspondent and date; sure 11/12 (all missed DM drogerie -> Egyeb instead of Egeszseg, arguably acceptable); tool call with correct name and arguments
- [observation] Hungarian free-text quality is noisy on a 10-prompt sample: the same Qwen weights named Jokai as the author of Toldi in one run and Arany in the next. Stable patterns across runs: Gemma corrects spelling flawlessly (Qwen failed the same item twice: "elkezdt"/"elkezdet"); Qwen answers with one result, Gemma tends to list several variants on rewrite/translate prompts; Gemma QAT produced odd words ("tuzetni", "megsemmisul") and denied Toldi exists
- [observation] Hungarian lexical/world knowledge matters for free chat in Open WebUI, much less for paperless (answer is in the document) and sure (classification from a given list; chat answers come from tool results)
- [observation] Newer models checked 2026-10-12: Qwen3.8 family exists (Flash-Next 125B/6B active: GGUF >= 78 GB, does not fit; 27B dense: too slow on CPU); no Gemma 5; Gemma 4 QAT + MTP drafter evaluated above
- [observation] Memory: Qwen3.6 pod ~20 GiB working set; node apiserver p99 stayed 4-14 ms during the runs (same as idle)
- [gotcha] Model switches that download multi-GB files outlive the HelmRelease 10m timeout -> upgrade fails -> Flux remediation rolls back to the previous release; if the downloader already pruned that release's GGUF, the rolled-back pod crashloops. Recovery: flux reconcile hr llama-cpp -n ai --force once the files are on the PVC (no download on the retry, upgrade succeeds)
- [done] Downloader (download-models.sh): prunes GGUFs no longer listed in models.conf; if a file name is re-pinned to a different sha256, the old file is discarded instead of resumed

## Next
- [next] Roadmap: revise the 10 tok/s gate to the measured ~7-8 tok/s ceiling (owner decision) and record the pick
- [next] Optional real-data validation before wiring consumers: ~20 real paperless OCR texts vs current mistral-large output, 50-100 real sure transactions, a multi-step tool-calling scenario (needs owner consent for real data)
- [next] Plan step 5: paperless-gpt and sure as consumers (own API keys via ExternalSecret, CNP egress to ai/llama-cpp)
- [next] Consider progressDeadlineSeconds / download Job split if model switches remain frequent (see gotcha)

## Relations

- implements [[local-ai-stack]]
