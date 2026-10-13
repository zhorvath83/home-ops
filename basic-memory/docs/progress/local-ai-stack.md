---
title: local-ai-stack
type: progress-note
permalink: home-ops/docs/progress/local-ai-stack
status: done
priority: medium
topic: Self-hosted LLM inference stack in a new ai namespace - llama.cpp server (Qwen3.6-35B-A3B
  UD-Q4_K_XL, bake-off winner 2026-10-12, CPU-only) and Open WebUI talking directly
  to its OpenAI-compatible API behind Pocket ID OIDC - no cloud fallback, model always
  resident
scope: One new app group kubernetes/apps/ai/ with namespace ai and two apps in one
  MVP wave - llama-cpp (bjw-s app-template HelmRelease, curl-based HF download init
  container, model PVC without VolSync, envoy-internal HTTPRoute, ServiceMonitor +
  Grafana dashboard), open-webui (official chart, native Pocket ID OAuth, VolSync
  on data PVC). LLMKube operator deliberately not used for the chat model. paperless-gpt
  and sure wired as consumers 2026-10-12.
rationale: 'The node has no usable inference GPU (Intel iGPU only, shares DDR4 bandwidth)
  and 45 GiB actually free RAM at ~6% CPU - Q4-quantized MoE models with ~3-4B active
  parameters are the only class that delivers usable Hungarian chat on CPU (measured
  ceiling 7-8 tok/s on the i7-10700T). Two current-generation candidates fit that
  class - Qwen3.6-35B-A3B (201 languages, strongest tool calling, hybrid Gated DeltaNet
  = small KV cache at long context) and Gemma 4 26B-A4B (140+ languages, Gemma family
  holds the best measured Hungarian scores). Neither has a published Hungarian benchmark,
  so a bake-off on the live node decided (2026-10-12: Qwen3.6 won decode and prefill
  at equal task accuracy; sure chat hard-requires tool calling, which both cleared).
  Dense models are too slow, GLM-4.5-Air too large, gpt-oss-20b weak in Hungarian,
  Hungarian-adapted models (PULI, Racka-4B) not competitive per the independent "Made
  in Hungary" re-evaluation.'
related_areas:
- k8s-workloads
- networking
- iam
- external-secrets
- observability
- flux-gitops
tags:
- ai
- llm
- llama-cpp
- open-webui
- qwen3
- gemma
- hungarian
---

# local-ai-stack — progress (roadmap merged in, item complete)

> Branch: `feat/local-ai-stack` (PR #4510)
> Status: **done** — roadmap item closed and merged into this note 2026-10-13, per repo convention.
> MVP wave live 2026-10-11; bake-off decided 2026-10-12 (Qwen3.6 35B-A3B, no MTP, 2 slots); paperless-gpt + sure wired 2026-10-12.

## Metadata (observation-form)

- [topic] Local AI inference stack — llama.cpp (Qwen3.6-35B-A3B, bake-off winner) + Open WebUI, ai namespace, no cloud fallback — roadmap + execution record in one note
- [status] done — 2026-10-13: roadmap merged into this note and closed (owner decision). MVP live 2026-10-11 (PR #4510); bake-off 2026-10-12: Qwen3.6 35B-A3B, no MTP, 2 slots; real-data validation 2026-10-12; consumers wired 2026-10-12. Remaining items are owner-side follow-ups, non-blocking (see Follow-ups)
- [priority] medium
- [area] k8s-workloads / networking / iam / external-secrets / observability / flux-gitops
- [branch] feat/local-ai-stack
- [created] 2026-10-11 (roadmap + MVP wave), 2026-10-13 (roadmap merged in)
- [effort] M — one new app group with two apps in one MVP wave, all riding existing planes (app-template pattern, ESO/onepassword-connect, envoy-internal HTTPRoute, native Pocket ID OAuth, ServiceMonitor/Prometheus)

## Roadmap origin (merged from docs/roadmap/local-ai-stack, closed 2026-10-13)

Self-hosted, purely local LLM stack on the existing single Talos node (HP ProDesk 600 G6, 16 vCPU, 64 GiB RAM, no inference-grade GPU — Intel iGPU only): a llama.cpp server hosting a CPU-friendly Hungarian-capable chat model, and Open WebUI as the chat frontend talking directly to the llama.cpp OpenAI-compatible API, behind Pocket ID OIDC. Reference architecture: eleboucher/homelab kubernetes/apps/ai (llama-cpp + litellm + litellm-operator + open-webui + memini + llmkube-for-embeddings), adapted to this repo's canonical app shape (their local llama-cpp path is currently inactive — see Research findings).

### Hardware baseline (measured 2026-10-11, live cluster)

- [observation] Single node k8s-cp0: 16 vCPU (8 physical cores with SMT — llama.cpp threads should follow physical cores), 64 GiB RAM; i7-class desktop CPU with DDR4 dual-channel (~40 GB/s memory bandwidth), AVX2 class. No discrete GPU (no nvidia.com/gpu), BUT an Intel iGPU is exposed via DRA (kubernetes/components/gpu, deviceClassName gpu.intel.com) and used by jellyfin (kubernetes/apps/media/jellyfin/ks.yaml) — corrected 2026-10-11, the original "no GPU" claim was wrong.
- [observation] The iGPU shares the same DDR4 bandwidth, so it gives no token-generation gain; at most a Vulkan prompt-processing experiment, which would contend with jellyfin transcoding. CPU path stays the plan.
- [resolved] Confirm the exact CPU model and core count on the node (read-only talosctl/kubectl node info) before fixing --threads — i7-10700T, 8 cores / 16 threads, AVX2+FMA (no AVX-512), threads=6 (see Execution, Measured baseline)
- [observation] Actual usage at measurement: 998m CPU (6%), 18.3 GiB memory (29%); requests 2024m CPU / 11 GiB, limits 11750m CPU / 60 GiB (limits near-capacity, requests-based scheduling leaves room).
- [observation] Consequence: CPU-only inference via llama.cpp GGUF; MoE models with small active-parameter counts are the only usable speed class; dense models above ~14B are too slow for chat.
- [resolved] Disk capacity — ~860 GiB available of 1 TB ephemeral/local storage; the 50 Gi model PVC is no concern (see Execution, Measured baseline)

### Research findings

- [observation] Hungarian LLM landscape 2026: the independent re-evaluation "Made in Hungary" (arXiv 2609.18284) found data contamination in PULI/OTP evaluations and showed international base models (Qwen3, Llama 3.1) match or beat the Hungarian-adapted models (PULI-LlumiX, Racka-4B) on most generative tasks; adapted models win only on spelling/grammar-style linguistic tasks.
- [observation] Qwen3-30B-A3B-Instruct-2507: 30.5B total / 3.3B active MoE, Q4_K_M GGUF ~19 GB, Apache-2.0, official claim 100+ languages, 2507 revision targets long-tail language knowledge; no published Hungarian benchmark (validation prompt set required — see acceptance criteria).
- [observation] Gemma 3 27B: only fitting model with measured Hungarian scores (HuGME — HuMMLU 68.86, HuTruthfulQA 67.07 — beats PULI family and SambaLingo 70B, approaches Llama-3.3-70B) but dense-27B on this CPU is ~3-5 tok/s; weak spelling (50.00). Deferred as a possible second model for quality-critical batch tasks.
- [observation] GLM-4.5-Air (106B MoE, 12B active, MIT): Q4_K_M GGUF 73.5 GB (bartowski) — does not fit; IQ2_M 45.12 GB is borderline and degraded; no Hungarian measurements published.
- [observation] gpt-oss-20b: official MMMLU covers 14 languages, Hungarian absent; independent evaluation (arXiv 2508.12461) found multilingual weakness; community Hungarian LoRA (csokosgeza/gpt-oss-20b-hun-4bit) exists to patch the gap — base model unsuitable for Hungarian out of the box.
- [observation] Racka-4B (elte-nlp): Hungarian-adapted Qwen3-4B, CC-BY-NC-SA gated research license, explicitly unaligned/unsafe for end users; GGUF available (Q4_K_M 2.5 GB) — not chosen; a future edge-model niche is not excluded if a concrete consumer appears.
- [observation] Model research refresh (2026-10-11): the original evaluation missed the Qwen3.5/Qwen3.6 generation and Gemma 4. Qwen3.6-35B-A3B — ~3B active of 35B (256 experts, top-8), hybrid Gated DeltaNet layers, 201 languages, 256K context, Apache-2.0; GGUF UD-Q4_K_M 20.6-22.1 GB, UD-Q4_K_XL 22.4 GB, Q5_K_M 26.5 GB, Q6_K 29.3 GB; hybrid thinking ON by default (disable with --chat-template-kwargs '{"enable_thinking":false}'). Sources: https://unsloth.ai/docs/models/qwen3.6 , https://insiderllm.com/guides/best-way-run-qwen-3-6-35b-moe-locally/
- [observation] Gemma 4 26B-A4B — 25.2B total / 3.8B active (128 experts, 8 active), 140+ languages, 256K context, Q4_K_M GGUF 16.8 GB. CPU-only data point: ~7 tok/s on an i5-8500 (6 cores, DDR4, no GPU). Sources: https://www.jetson-ai-lab.com/models/gemma4-26b-a4b , https://www.kunalganglani.com/blog/gemma-4-cpu-inference-benchmark.md
- [observation] Head-to-head (dense Gemma 4 31B vs Qwen3.6 35B-A3B): Qwen3.6 wins agentic tool use (TAU2 +13), Gemma 4 wins multilingual reasoning and human preference — https://regolo.ai/gemma-4-31b-vs-qwen3-6-35b-a3b-when-to-use-which/ . No Hungarian benchmark found for any 2026 model.
- [observation] Early llama.cpp builds ran Qwen3.5-35B-A3B ~35% slower than Qwen3-30B-A3B (CUDA, Gated DeltaNet implementation); no pure-CPU number found — the CPU path must be measured, not assumed.
- [observation] Sure AI contract (https://mintlify.wiki/we-promise/sure/hosting/ai-features): OPENAI_URI_BASE + OPENAI_MODEL (mandatory for custom providers) + OPENAI_ACCESS_TOKEN; chat assistant REQUIRES tool calling, auto-categorization and merchant detection do not; document search needs a vector store (embeddings). Sure's own docs name qwen3-30b as best local chat model.
- [observation] paperless-gpt today (kubernetes/apps/selfhosted/paperless-gpt/app/helmrelease.yaml): LLM_PROVIDER mistral, LLM_MODEL mistral-large-latest, LLM_LANGUAGE Hungarian, OCR_PROVIDER mistral_ocr. A local model replaces only the LLM part; OCR stays on Mistral cloud. mistral-large -> ~3B-active local is a quality-downgrade risk, so paperless tasks are part of the bake-off.
- [observation] Reference architecture (eleboucher/homelab, kubernetes/apps/ai; in-depth review 2026-10-11): the llama-cpp app below is INACTIVE in their current tree (commented out of the group kustomization) — their litellm now serves cloud ChatGPT models via the litellm-operator CRDs (ChatGPT-subscription compat shim). The inactive local shape we adapt: plain llama.cpp server Deployment (bjw-s app-template — uv+huggingface_hub init container downloads GGUF to a PVC, ghcr.io/ggml-org/llama.cpp server, /health probes, LLAMA_API_KEY from secret); LLMKube operator kept ONLY for embedding+reranker models (Qwen3-Embedding-0.6B / Qwen3-Reranker-0.6B); open-webui as frontend (Kanidm OIDC); memini as agent memory. Their llama-cpp uses a Vulkan build with /dev/dri hostPath (they have a GPU) — this cluster needs the plain CPU server image instead.
- [observation] Reference in-depth review (2026-10-11): a purely-local stack has no direct equivalent in their current tree — the local llama-cpp route is an earlier iteration; local backends enter their litellm only via llmkube autoRegister (embeddings/rerank). Their llama-cpp ran privileged: true with /dev/dri hostPath for the Vulkan build — our CPU image stays unprivileged. Their inactive chat model was gemma-4-E4B-it UD-Q8_K_XL (~4.4 GB, multimodal, no measured Hungarian scores) — noted as a future candidate our model evaluation missed.

### Decisions (owner-ratified 2026-10-11)

- [decision] MVP scope — two apps in one wave (llama-cpp + open-webui); LiteLLM dropped (see below).
- [decision] No cloud fallback — purely local; no AI API key leaves the house.
- [decision] Model always resident in memory (~20 GB); no idle-unload.
- [decision] llama-cpp must NOT receive the kubernetes/components/zeroscaler component (HPA scale-to-zero) — the always-resident guarantee excludes idle-downscaling; recorded so a future cleanup cannot silently break it.
- [decision] New app group kubernetes/apps/ai/ with a dedicated ai namespace.
- [decision] llama.cpp server Deployment chosen over LLMKube operator for the chat model (single model = no operator machinery; LLMKube revisit trigger — multi-model orchestration, multi-runtime, or inference-metric HPA).
- [decision] Model PVC excluded from VolSync (regenerable); open-webui chat-history PVC included.
- [decision] Chat model (owner decision 2026-10-11, supersedes Qwen3-30B-A3B-Instruct-2507): Qwen3.6-35B-A3B UD-Q4_K_XL provisional, confirmed or replaced by Gemma 4 26B-A4B through the bake-off gate (Plan step 4). Qwen3-30B-A3B-2507 is fallback only.
- [decision] Bake-off pick (owner decision 2026-10-12): Qwen3.6-35B-A3B UD-Q4_K_XL, served without MTP, 2 slots. Both candidates cleared tool calling and scored equal on the paperless/sure-shaped synthetic sets; Qwen won decode (7.2-8.1 vs 7.1-7.5 tok/s) and prefill (251 s vs 322 s on a ~9k prompt); Hungarian free-text quality was too noisy on a 10-prompt sample to separate them (Gemma steadier at spelling, Qwen at single-answer instruction following). Real-data validation of the paperless/sure sets follows before Plan step 5. Full numbers: Execution, Bake-off section.
- [decision] Target consumers (owner direction 2026-10-11): Open WebUI first; paperless-gpt and sure are wired to the llama-cpp endpoint in follow-up PRs once the bake-off gate passes.
- [decision] LiteLLM dropped from the MVP (owner decision 2026-10-11) — one local backend, no cloud fallback, no API cost to track and a single consumer make the gateway (and the Postgres it needs for virtual keys / spend logs) speculative; llama.cpp server already provides the OpenAI-compatible API, API-key auth and --metrics. Revisit trigger — a second backend, a cloud fallback route, or per-consumer quotas/usage accounting; per-consumer keys alone do not trigger it (llama-server accepts multiple API keys — verify on the pinned version). Consumers then repoint to the LiteLLM URL.

### Plan (one MVP wave, ordered — all steps executed)

1. Group scaffolding: kubernetes/apps/ai/ (namespace.yaml, kustomization.yaml, per-app
   ks.yaml + app/ shape, cluster-root ks.yaml registration).
2. llama-cpp app: app-template HelmRelease, CPU llama.cpp server image (digest-pinned, `# renovate:` annotation per repo convention),
   uv + huggingface_hub init container downloading the bake-off GGUFs (Qwen3.6-35B-A3B
   UD-Q4_K_XL ~22.4 GB + Gemma 4 26B-A4B Q4_K_M ~16.8 GB; only the winner stays)
   to a local-hostpath PVC (50 Gi), -c 32768 context, flash-attn, LLAMA_API_KEY via
   ExternalSecret (onepassword-connect, 12h refresh), requests ~26Gi memory (weights ~22.4 GB mmap-resident for Qwen3.6 + KV cache — small for the hybrid DeltaNet / sliding-window architectures, re-measure in the bake-off — + runtime overhead; --parallel 2 so a paperless/sure batch does not block chat; -ctk/-ctv q8_0 KV quantization is the headroom lever), no CPU limit but an explicit CPU request and --threads <= 6 (8 physical cores; the control plane shares this node), Qwen3.6 thinking disabled via --chat-template-kwargs, /health probes with generous startup budget (model load),
   CiliumNetworkPolicy (egress to huggingface.co + cdn-lfs.huggingface.co +
   cas-bridge.xethub.hf.co needed by the init container — the actual download comes from
   the HF CDNs, a huggingface.co-only allowlist would break it; Cilium policy is pod-scoped,
   so the server container inherits this egress — accept it or move the download into a
   separate Job; ingress from ai/open-webui and later selfhosted/paperless-gpt + selfhosted/sure),
   envoy-internal HTTPRoute (LAN API surface + testing).
   Reference-adopted implementation details: download script as ConfigMap mounted into
   the init container (`hf download --include '*Q4_K_M*.gguf'` + stable `model.gguf`
   symlink into the HF snapshot dir so the server argument survives model-revision
   updates); HF_TOKEN env in the init container (optional — the models are not gated; rate limits only); init writes the model PVC,
   server mounts it readOnly; `--metrics` on the llama server for native Prometheus
   metrics (ServiceMonitor into existing Prometheus — bearer auth from the LLAMA_API_KEY
   secret if /metrics sits behind --api-key, verify on the pinned server version — plus
   the reference's llama-server.json Grafana dashboard via the observability area's
   existing dashboard provisioning pattern); `--alias` for a stable model id; ks.yaml `wait: false` + `timeout: 1h`
   (model download init exceeds default health-check windows); startup probe budget
   ~60x10s. Flag decisions to record at implementation: mmap-resident (chosen) vs
   `--no-mmap` (reference measured OOM at a 2Gi limit during load, ~7.9Gi peak) and
   `--sleep-idle-seconds` as the future idle-softening lever (server flag, not a
   component swap).
3. open-webui app: official Helm chart (bundled ollama/pipelines sub-components disabled),
   auth per the open OIDC decision (gateway-oidc component OR native OAuth — not both),
   Pocket ID client (per-app group ACL pattern; port the reference OIDC env checklist — OAUTH_SCOPES,
   OAUTH_CODE_CHALLENGE_METHOD S256, OAUTH_ROLES_CLAIM groups +
   OAUTH_ALLOWED_ROLES/OAUTH_ADMIN_ROLES, ENABLE_OAUTH_ROLE_MANAGEMENT,
   ENABLE_LOGIN_FORM false, ENABLE_SIGNUP false; pin the llama-cpp backend in env
   (OPENAI_API_BASE_URL to the llama-cpp Service /v1, OPENAI_API_KEY from the LLAMA_API_KEY
   secret) rather than admin-UI/db-only), background task model (title/tag generation)
   disabled or pinned so it does not queue behind chat, VolSync component on the chart's existing data PVC (chats live in webui.db there — no separate chat-history PVC),
   envoy-internal exposure first (public exposure is a separate later decision).
4. Model bake-off + validation gate (acceptance criteria, run on the live stack; both
   candidates on the same node, same flags, one at a time):
   - Candidates: Qwen3.6-35B-A3B UD-Q4_K_XL (thinking off) vs Gemma 4 26B-A4B Q4_K_M;
     optional quant check Q4 vs Q5_K_M for the winner (Hungarian is quantization-sensitive,
     Q5 costs ~20-30% speed).
   - Hungarian prompt set (10-15 prompts — spelling correction, register rewrite,
     Hungarian summarization, factual Hungarian QA) judged subjectively acceptable.
   - paperless set: 5 real Hungarian OCR texts -> title / tags / correspondent as valid JSON,
     compared against the current mistral-large output.
   - sure set: categorize ~20 real transactions + one tool-calling round (chat assistant
     contract).
   - Throughput: decode >= 7 tok/s sustained (revised 2026-10-12 by owner decision from >= 10:
     every candidate measured 7-8 tok/s on the i7-10700T — the ceiling of this model class on
     DDR4 dual channel; MTP speculative decoding measured slower, see Execution, Bake-off section)
     AND time-to-first-token measured on an 8k-token prompt (CPU prefill is the real
     bottleneck for paperless documents).
   - Node health under load: apiserver/etcd latency stays normal while the model generates.
   - Decision rule: tool-calling failure disqualifies (sure chat); otherwise Hungarian
     quality wins over speed if both clear 7 tok/s. Record results + the pick in this note.
   - llama-cpp answers /v1/models and a completion with the API key; llama.cpp
     --metrics visible in Grafana.
   - Open WebUI login via Pocket ID works; a chat round-trip completes.
5. Follow-up consumers (separate PRs, only after the gate passes): paperless-gpt
   (OpenAI-compatible provider -> llama-cpp Service, OCR stays Mistral) and sure
   (OPENAI_URI_BASE / OPENAI_MODEL / OPENAI_ACCESS_TOKEN); each with its own API key via
   ExternalSecret and a CNP egress rule to ai/llama-cpp.

### Review findings (2026-10-11)

- [finding] GPU claim corrected — the cluster exposes an Intel iGPU via DRA (components/gpu, gpu.intel.com, used by jellyfin); no decode gain on shared DDR4, CPU path stays (see Hardware baseline).
- [finding] Model choice was a generation behind — Qwen3.5/3.6 and Gemma 4 were not evaluated; replaced by the bake-off (Plan step 4) with Qwen3.6-35B-A3B provisional.
- [finding] Throughput expectation was optimistic — 15-25 tok/s corrected to 8-15 tok/s; time-to-first-token added as a criterion.
- [finding] Double OIDC in the original plan — gateway-oidc component (Envoy-native login gate) AND Open WebUI native OAUTH_* env would mean two logins and two Pocket ID clients; one must be chosen (open question below).
- [finding] CNP cannot scope egress to an init container — Cilium identity is per pod, so the HuggingFace egress also applies to the server container; accept or use a separate download Job.
- [finding] CPU starvation risk — no CPU limit on a single node that also runs the control plane; mitigated by --threads <= 6, an explicit CPU request and a node-health check in the gate.
- [finding] Multiple consumers on one slot — Open WebUI background tasks and paperless/sure batches would queue behind chat; --parallel 2 and a disabled/pinned Open WebUI task model.
- [finding] paperless-gpt open question answered — it uses Mistral cloud (LLM + OCR); see Research findings.
- [finding] Minor — HF_TOKEN optional (models not gated); Open WebUI chart sub-components (ollama, pipelines) must be disabled.

### Open questions (at roadmap close)

- [resolved] Open WebUI auth model: chosen (b) — native Open WebUI OAuth against Pocket ID without the component (owner decision 2026-10-11, see Execution, Decisions taken at implementation).
- [resolved] paperless-gpt OCR stays on Mistral cloud even after the LLM moves local — accepted 2026-10-12; paperless-gpt wired with the local OpenAI-compatible LLM and OCR mistral_ocr retained (Mistral egress kept).
- [deferred] Public exposure of Open WebUI (envoy-external + Cloudflare Tunnel + OIDC group ACL) — tracked in Follow-ups.
- [deferred] Embeddings/RAG plane (llmkube or TEI + memini) — tracked in Follow-ups; sure's document search (vector store) is a concrete candidate consumer.

## Execution

### Decisions taken at implementation (owner, 2026-10-11)

- [decision] Open WebUI auth: native OAuth against Pocket ID (no gateway-oidc), PKCE S256, OAuth config env-authoritative (ENABLE_OAUTH_PERSISTENT_CONFIG=false)
- [decision] Access group: infra_admins (both allowed and admin role)
- [decision] Hostnames: chat.${PUBLIC_DOMAIN} (open-webui), llm.${PUBLIC_DOMAIN} (llama-cpp API), both envoy-internal only
- [decision] Model download: plain curl init container against pinned HF revisions with sha256 verification (no python/uv, no PyPI egress); models listed in app/config/models.conf
- [decision] Per-consumer llama.cpp API keys (LLAMA_API_KEY is a comma list): open_webui_api_key, metrics_api_key in 1Password HomeOps/llama-cpp
- [decision] Thinking disabled via LLAMA_ARG_REASONING=off (generic switch, works for both candidates)

### Measured baseline (2026-10-11)

- [observation] CPU: Intel Core i7-10700T, 8 cores / 16 threads, AVX2+FMA (no AVX-512) — threads=6
- [observation] Node ephemeral/local storage: ~860 GiB available of 1 TB — 50Gi model PVC is no concern

### Done

- [done] Commits 109b907d8 (renovate regex versioning for server-b<build>) and cd251c543 (ai stack), pushed, PR #4510
- [done] 1Password items HomeOps/llama-cpp and HomeOps/open-webui created with random 64-hex values
- [done] Validation: kustomize build (3 trees), helm template of both charts, pre-commit, just pocket-id lint — all green

### Blocked

- [resolved] 2026-10-11: the Pocket ID provisioning API key had expired (HTTP 401); owner rotated it in HomeOps/pocket-id. terraform plan showed exactly 1 add (pocketid_client open-webui), applied; sync-secrets wrote open-webui_client_secret (run through `script -q /dev/null` so op gets a pty — avoids the piped-stdin gotcha); `just pocket-id audit` reports all 25 clients group-restricted.

### Live verification (2026-10-11)

- [verified] Downloads: both GGUFs sha256 OK (Qwen3.6 20.82 GiB at ~65 MB/s); restarts skip via .verified markers
- [verified] llama-cpp: /health 200 without key; /v1/models and /metrics 401 without key; /v1/models with key -> [qwen3.6-35b-a3b]; n_slots=2, n_ctx_slot=16384 (kv_unified=false); pod memory ~20.3 GiB resident
- [verified] open-webui -> llama-cpp path (CNP + per-consumer key) answers Hungarian prompts; reasoning_content empty (thinking off works)
- [verified] Prometheus target up{job=llama-cpp}=1, llamacpp:* metrics present; GrafanaFolder ai + GrafanaDashboard llama-server synchronized
- [verified] Open WebUI: runs with readOnlyRootFilesystem (STATIC_DIR emptyDir), offline embedding model loads from the bundled cache, /api/config shows only the Pocket ID provider, login redirect carries PKCE S256; owner confirmed working login
- [measured] Qwen3.6 UD-Q4_K_XL, threads=6: generation 6.3-6.6 tok/s, prompt processing 13-18 tok/s on short prompts — BELOW the >=10 tok/s gate. Quality spot-check: summary fluent and correct; spelling-fix final sentence correct but the explanation contained wrong claims
- [fixed] CNP: HF resolve redirects to us.aws.cdn.hf.co; single-label *.hf.co was POLICY_DENIED (Hubble) -> **.hf.co / **.huggingface.co (Cilium 1.20)
- [fixed] CORS_ALLOW_ORIGIN restricted to the chat origin (startup warned on '*')
- [gotcha] First rollout outlives the injected 10m HelmRelease timeout and the Deployment's 600s progressDeadline -> HR InstallFailed, then Deployment stuck Progressing=False (kstatus Failed, rollback impossible). Recovery: kubectl rollout restart deploy/llama-cpp + flux reconcile hr --force. One-off per fresh PVC; recurs only if a new model is added to models.conf

### Open WebUI prompt bloat (2026-10-11)

- [measured] 8 threads (1dca74fe5): decode 7.4 tok/s (6 threads: 6.3-6.6), prompt processing ~26-33 tok/s; still below the 10 tok/s gate
- [problem] Open WebUI v0.12 native function calling attaches builtin tool schemas to every chat: ~7.2-7.7k prompt tokens => ~4 min to first token on cold cache (worse with 2 concurrent slots)
- [gotcha] Open WebUI snapshots ALL config keys (368 rows, table config) into webui.db on first boot; afterwards the DB row wins over env, so later env changes are silently ignored. Fix 4dbb3ed06: ENABLE_PERSISTENT_CONFIG=false — env/git is authoritative on every start; admin UI changes do not survive a restart
- [fixed] 1e907687d (ENABLE_MEMORIES/NOTES/CODE_INTERPRETER/CODE_EXECUTION=false) + 0d30d3a0c (DEFAULT_MODEL_METADATA capabilities.builtin_tools=false; ef27774c2 knowledge-only variant superseded). Measured after: new chat prompt 19-38 tokens, first token ~1-2 s, decode 5.9-7.3 tok/s
- [observation] Intermediate step with only memories/notes/code off: prompt ~4.0k tokens (time, ask_user, chats tools + their instructions remained)

### Bake-off (2026-10-12)

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
- [measured] The 10 tok/s gate is not reachable with this model class on an i7-10700T (DDR4 dual channel): every variant decodes at ~7-8 tok/s. The gate was revised to >= 7 tok/s by owner decision 2026-10-12
- [observation] Accuracy on consumer-shaped tasks was identical across all four variants: paperless 3/3 valid JSON with correct correspondent and date; sure 11/12 (all missed DM drogerie -> Egyeb instead of Egeszseg, arguably acceptable); tool call with correct name and arguments
- [observation] Hungarian free-text quality is noisy on a 10-prompt sample: the same Qwen weights named Jokai as the author of Toldi in one run and Arany in the next. Stable patterns across runs: Gemma corrects spelling flawlessly (Qwen failed the same item twice: "elkezdt"/"elkezdet"); Qwen answers with one result, Gemma tends to list several variants on rewrite/translate prompts; Gemma QAT produced odd words ("tuzetni", "megsemmisul") and denied Toldi exists
- [observation] Hungarian lexical/world knowledge matters for free chat in Open WebUI, much less for paperless (answer is in the document) and sure (classification from a given list; chat answers come from tool results)
- [observation] Newer models checked 2026-10-12: Qwen3.8 family exists (Flash-Next 125B/6B active: GGUF >= 78 GB, does not fit; 27B dense: too slow on CPU); no Gemma 5; Gemma 4 QAT + MTP drafter evaluated above
- [observation] Memory: Qwen3.6 pod ~20 GiB working set; node apiserver p99 stayed 4-14 ms during the runs (same as idle)
- [gotcha] Model switches that download multi-GB files outlive the HelmRelease 10m timeout -> upgrade fails -> Flux remediation rolls back to the previous release; if the downloader already pruned that release's GGUF, the rolled-back pod crashloops. Recovery: flux reconcile hr llama-cpp -n ai --force once the files are on the PVC (no download on the retry, upgrade succeeds)
- [done] Downloader (download-models.sh): prunes GGUFs no longer listed in models.conf; if a file name is re-pinned to a different sha256, the old file is discarded instead of resumed

### Real-data validation (2026-10-12, owner-approved, read-only)

Qwen3.6 (no MTP, 2 slots), temperature 0.1. Read-only exports: tools/llm-bakeoff/paperless_export.py (Django shell ORM reads) and sure_export.rb (rails runner reads); evaluation tools/llm-bakeoff/realdata.py in the open-webui pod. Nothing was written back to paperless or sure; data moved paperless/sure pod -> kubectl on the owner's laptop (memory only, plus a local result file for owner review) -> open-webui pod -> local llama-cpp. Only aggregates recorded here.

- [measured] paperless, 15 most recent documents vs their current metadata (mostly set by paperless-gpt + Mistral, possibly hand-corrected): valid JSON 15/15, correspondent 12/15 (picked from 81), document type 14/15 (from 17), created date 11/15, tags recall 0.97 / precision 0.56 (over-tags: ~3 per doc vs 1.7 current), ~50 s per document (max 91 s) with the choice lists cached as system prompt
- [measured] sure, all 41 categorised transactions (only 4 distinct categories; model saw name, merchant, amount and the flat 70-category list): 22/41 correct. Error pattern: takeaway food split across other categories, parking -> sibling car/other categories, groceries -> other costs
- [measured] multi-step tool calling (synthetic, 2 tools): list_accounts -> get_transactions(acc-1, 2026-10) -> correct sum
- [conclusion] paperless-gpt LLM part is viable on the local model; its tag prompt needs to restrain over-tagging; created-date mismatches need owner review (issue vs performance date ambiguity)
- [conclusion] sure chat assistant (tool calling, read-only answers) is viable; sure AI auto-categorisation is NOT recommended at 54% — it writes categories onto transactions
- [caveat] Small samples; sure sample covers only 4 categories; the paperless baseline is not a pure Mistral output

### Consumers wired (2026-10-12, Plan step 5, owner decision "wire everywhere, then see")

- [done] e71166b70: per-consumer keys paperless_gpt_api_key + sure_api_key added to 1Password HomeOps/llama-cpp; LLAMA_API_KEY now lists open-webui, metrics, paperless-gpt, sure; llama-cpp CNP ingress from selfhosted paperless-gpt and sure
- [done] paperless-gpt: LLM_PROVIDER openai + LLM_MODEL qwen3.6-35b-a3b + OPENAI_BASE_URL http://llama-cpp.ai.svc.cluster.local:8080/v1 (honoured for non-Azure openai, paperless-gpt main.go:1224); OPENAI_API_KEY via its ExternalSecret; OCR stays mistral_ocr; CNP egress to ai/llama-cpp:8080 added (Mistral egress kept for OCR)
- [done] sure: OPENAI_ACCESS_TOKEN / OPENAI_URI_BASE (with /v1, per sure docs) / OPENAI_MODEL in sure-secret so server and worker share the provider; CNP egress to ai/llama-cpp:8080. Custom provider uses Chat Completions (no Responses endpoint)
- [verified] sure-server: Provider::Registry.preferred_llm_provider = Custom OpenAI-compatible (llama-cpp); GET /v1/models with sure's key -> 200 qwen3.6-35b-a3b. No live sure chat was triggered (it would write LLM usage rows)
- [verified] paperless-gpt restarted cleanly (OCR mistral_ocr valid, workers up); end-to-end needs one document tagged AI-processing (owner action — it writes metadata)
- [observation] sure AI categorisation / merchant detection only run through user-created Rules (Rule::ActionExecutor::AutoCategorize / AutoDetectMerchants are the only callers) and only touch enrichable (unlocked) categories — wiring alone writes nothing
- [observation] Backups before wiring: paperless + paperless-gpt VolSync 2026-10-12 ~05:02 UTC successful; sure DB covered by the database/postgres-backup CronJob (daily 00:17)
- [risk] Real-data validation predicted paperless over-tagging (precision 0.56) and weak sure categorisation (22/41); the paperless-gpt tag prompt lives in its PVC (/app/prompts, editable in its UI), not in git

### Sure tuning for the local model (2026-10-12)

- [fixed] 7a06ad612 OPENAI_REQUEST_TIMEOUT=600: first chat died with Net::ReadTimeout at the 60 s default (Provider::Openai::DEFAULT_REQUEST_TIMEOUT); the client-wide option also covers categorisation and merchant detection
- [fixed] 5b18da83b AI_RESPONSE_TIMEOUT=600: the browser watchdog (Chat::DEFAULT_RESPONSE_TIMEOUT 90 s) POSTed report_timeout and marked the reply dead while the worker finished it at 194 s
- [fixed] 6845099fa LLM_CONTEXT_WINDOW=16384: sure sized AI batches against a 2048-token default (Assistant::TokenBudget::DEFAULT_CONTEXT_WINDOW); max 25 items per call
- [fixed] 66b29dcd6 LLM_CONTEXT_WINDOW=10240 (superseding 16384): sure estimates tokens as chars/4 x safety factor, which undercounts Hungarian text and JSON tool results; at 16384 a two-turn chat with transaction tool results reached the 16384-token slot (reply truncated, then HTTP 400 "request (16399 tokens) exceeds the available context size"). 10240 leaves ~35% headroom for estimator error and the reply
- [measured] sure chat turns with tool results took 270-350 s each (prefill 7.9-8k uncached tokens at 27-30 tok/s); this is the realistic pace for sure chat on this node
- [measured] sure chat prompt = 8372 tokens (system prompt + function tool schemas); cold prefill ~176 s at ~36 tok/s; completion ~6 tok/s. Prefix cache helps follow-ups only while the slot keeps it
- [note] All four live in sure-secret (shared by server and worker), verified in the worker: ctx=16384 items=25 http=600s watchdog=600s

### Sure chat assessment + categorisation trial (2026-10-12)

- [measured] After the timeout/context fixes the sure chat no longer fails, but turns take 150-350 s and quality is uneven: of 4 replies, one started in English, two stopped after ~7 tokens ("## ..." heading only), one was a correct Hungarian summary. Cause of the short replies not investigated (candidates: sure's max_tokens under the reduced budget, or a malformed tool call)
- [decision] Owner: try AI categorisation on uncategorised transactions instead of pursuing the chat
- [done] Trial on 25 of 88 uncategorised standard transactions (most recent by entry date), run synchronously via Family#auto_categorize_transactions in sure-server: 136 s; 19 categorised (Bayes 13, local LLM 6), 6 withheld as low-confidence (left blank, unlocked); only the 6 AI decisions are locked. Pre-run snapshot (ids, category_id, locked_attributes) kept on the owner's laptop for a revert
- [observation] Sure's BayesCategorizer runs before the LLM and learns from the family's existing categorised transactions; it handled half of the trial with no LLM call
- [next] Owner reviews the 19 in sure; then either run the remaining ~63 or revert the trial (set category_id nil + unlock for the snapshot ids)

### Follow-ups (owner, non-blocking)

- [done] 2026-10-13: roadmap merged into this note and the roadmap item closed per repo convention
- [next] Owner: tag one paperless document AI-processing and review the result; watch paperless-gpt logs for LLM errors/timeouts (~50 s per document expected)
- [next] If over-tagging shows up: tighten the paperless-gpt tag prompt (UI / PVC prompts), then consider moving prompts into git
- [next] sure: try the chat assistant; create an AI auto-categorise rule only if the quality is acceptable (22/41 on real data)
- [next] Consider progressDeadlineSeconds / download Job split if model switches remain frequent
- [open] Public exposure of Open WebUI (envoy-external + Cloudflare Tunnel + OIDC group ACL) — deferred
- [open] Embeddings/RAG plane (llmkube or TEI + memini) — deferred; sure's document search (vector store) is a concrete candidate consumer

## Related

- relates_to [[k8s-workloads]]
- relates_to [[networking]]
- relates_to [[iam]]
- relates_to [[external-secrets]]
- relates_to [[observability]]
- relates_to [[flux-gitops]]
- reference https://github.com/eleboucher/homelab/tree/main/kubernetes/apps/ai
- reference https://unsloth.ai/docs/models/qwen3.6
- reference https://www.jetson-ai-lab.com/models/gemma4-26b-a4b
- reference https://mintlify.wiki/we-promise/sure/hosting/ai-features
- reference https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507 (fallback)
