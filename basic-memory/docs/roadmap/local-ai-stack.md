---
title: local-ai-stack
type: roadmap
permalink: home-ops/docs/roadmap/local-ai-stack
topic: Self-hosted LLM inference stack in a new ai namespace - llama.cpp server (Qwen3.6-35B-A3B
  UD-Q4_K_XL provisional, Gemma 4 26B-A4B challenger in a bake-off, CPU-only), and Open WebUI talking directly to its OpenAI-compatible API
  behind Pocket ID OIDC - no cloud fallback, model always resident
status: in-progress
priority: medium
scope: One new app group kubernetes/apps/ai/ with namespace ai and two apps in one
  MVP wave - llama-cpp (bjw-s app-template HelmRelease, HF download init container,
  model PVC without VolSync, envoy-internal HTTPRoute, ServiceMonitor
  + Grafana dashboard), open-webui (official chart, gateway-oidc component
  + Pocket ID client, VolSync on chat-history PVC). LLMKube operator deliberately
  not used for the chat model. paperless-gpt and sure are follow-up consumers once the
  bake-off gate passes (separate PRs).
rationale: The node has no usable inference GPU (Intel iGPU only, shares DDR4 bandwidth)
  and 45 GiB actually free RAM at ~6% CPU - Q4-quantized MoE models with ~3-4B active
  parameters are the only class that delivers usable Hungarian chat on CPU (realistic
  ~8-15 tok/s on this node). Two current-generation candidates fit that class - Qwen3.6-35B-A3B
  (201 languages, strongest tool calling, hybrid Gated DeltaNet = small KV cache at long
  context) and Gemma 4 26B-A4B (140+ languages, Gemma family holds the best measured Hungarian
  scores). Neither has a published Hungarian benchmark, so a bake-off on the live node
  decides; Qwen3.6 is provisional default because sure's chat assistant hard-requires
  tool calling. Qwen3-30B-A3B-Instruct-2507 (the original pick) is a generation behind and
  kept only as fallback. Dense models are too slow, GLM-4.5-Air too large, gpt-oss-20b weak
  in Hungarian, Hungarian-adapted models (PULI, Racka-4B) not competitive per the independent
  "Made in Hungary" re-evaluation.
related_areas:
- k8s-workloads
- networking
- iam
- external-secrets
- observability
- flux-gitops
options:
- Plain llama.cpp server Deployment via app-template (chosen - single model needs
  no CRD machinery; revisit trigger — multiple models, multi-runtime mixing, or inference-metric
  HPA)
- LLMKube operator (rejected for MVP - operator + CRDs for exactly one Model and one
  InferenceService is speculative machinery)
- Qwen3.6-35B-A3B UD-Q4_K_XL as chat model (chosen provisionally 2026-10-11 - MoE ~3B
  active, ~22.4 GB, Apache-2.0, 201 languages, best tool calling in class (sure chat
  requirement), hybrid Gated DeltaNet keeps KV cache small; thinking must be disabled
  on CPU; final pick decided by the bake-off)
- Gemma 4 26B-A4B Q4_K_M as chat model (bake-off challenger - 3.8B active, ~16.8 GB,
  Apache-2.0, 140+ languages, Gemma family has the best measured Hungarian scores;
  weaker tool calling, ~15% slower per token than 3B-active models)
- Qwen3-30B-A3B-Instruct-2507 Q4_K_M (superseded 2026-10-11 - original pick, one
  generation behind Qwen3.5/3.6; kept only as fallback if the newer Gated DeltaNet CPU
  path misbehaves in llama.cpp)
- Gemma 3 27B IT QAT as first model (rejected for MVP, deferred as later second model
  - the only fitting model with MEASURED Hungarian scores (HuGME — HuMMLU 68.86, HuTruthfulQA
  67.07) but dense 27B on DDR4 CPU is ~3-5 tok/s, too slow for chat; candidate for
  quality-critical batch tasks)
- GLM-4.5-Air (rejected - Q4_K_M GGUF is 73.5 GB, far above the ~45 GiB actually free;
  IQ2/IQ3 variants that would fit are too degraded; no Hungarian measurements exist)
- gpt-oss-20b (rejected - officially evaluated on 14 languages, Hungarian not among
  them; independent evaluation found multilingual weakness; community needed a Hungarian
  LoRA to make it usable)
- Llama 3.3 70B (rejected - best-in-class dense Hungarian HuMMLU 74.02 but Q4 ~40
  GB dense weights mean <1.5 tok/s on this CPU)
- Racka-4B / PULI-LlumiX-Llama-3.1 (rejected - CC-BY-NC-SA gated research model, unaligned;
  "Made in Hungary" (arXiv 2609.18284) shows the Qwen3-4B base matches or beats it
  on most generative Hungarian tasks)
- Cloud fallback model (rejected by owner decision 2026-10-11 - purely local stack,
  no AI API key leaves the house)
- LiteLLM gateway (dropped for MVP by owner decision 2026-10-11 - single local backend,
  no fallback, no per-consumer keys needed; revisit trigger — second backend, cloud
  fallback, or a second consumer needing its own revocable key)
- Idle-unload the model (rejected by owner decision 2026-10-11 - always resident ~20
  GB; node has ample free memory at 18.3/64 GiB used)
- New kubernetes/apps/ai/ app group with ai namespace (chosen by owner decision 2026-10-11
  - matches reference repo grouping; AI workloads grow together)
- VolSync on the model PVC (rejected - GGUF weights are regenerable from HuggingFace;
  daily snapshots of 19+ GB are waste; chat-history PVC in open-webui DOES get VolSync)
tags:
- ai
- llm
- llama-cpp
- open-webui
- qwen3
- gemma
- hungarian
---

# Local AI stack — llama.cpp + Open WebUI in `ai` namespace

Self-hosted, purely local LLM stack on the existing single Talos node (HP ProDesk 600 G6,
16 vCPU, 64 GiB RAM, no inference-grade GPU — Intel iGPU only): a llama.cpp server hosting a CPU-friendly Hungarian-capable
chat model, and Open WebUI as the chat frontend talking directly to the llama.cpp
OpenAI-compatible API, behind Pocket ID OIDC. Reference architecture: eleboucher/homelab
kubernetes/apps/ai (llama-cpp + litellm + litellm-operator + open-webui + memini +
llmkube-for-embeddings), adapted to this repo's canonical app shape (their local llama-cpp path is currently inactive — see Research findings).

## Metadata (observation-form)

- [topic] Local AI inference stack — llama.cpp (Qwen3.6-35B-A3B provisional, Gemma 4 26B-A4B bake-off challenger) + Open WebUI, new ai namespace, no cloud fallback
- [status] in-progress — MVP wave live (2026-10-11), bake-off decided (2026-10-12); real-data validation and Plan step 5 open
- [priority] medium
- [area] k8s-workloads / networking / iam / external-secrets / observability
- [created] 2026-10-11
- [effort] M — one new app group with two apps in one MVP wave, all riding existing planes (app-template pattern, ESO/onepassword-connect, envoy-internal HTTPRoute, gateway-oidc component, ServiceMonitor/Prometheus)

## Hardware baseline (measured 2026-10-11, live cluster)

- [observation] Single node k8s-cp0: 16 vCPU (8 physical cores with SMT — llama.cpp threads should follow physical cores), 64 GiB RAM; i7-class desktop CPU with DDR4 dual-channel (~40 GB/s memory bandwidth), AVX2 class. No discrete GPU (no nvidia.com/gpu), BUT an Intel iGPU is exposed via DRA (kubernetes/components/gpu, deviceClassName gpu.intel.com) and used by jellyfin (kubernetes/apps/media/jellyfin/ks.yaml) — corrected 2026-10-11, the original "no GPU" claim was wrong.
- [observation] The iGPU shares the same DDR4 bandwidth, so it gives no token-generation gain; at most a Vulkan prompt-processing experiment, which would contend with jellyfin transcoding. CPU path stays the plan.
- [open] Confirm the exact CPU model and core count on the node (read-only talosctl/kubectl node info) before fixing --threads.
- [observation] Actual usage at measurement: 998m CPU (6%), 18.3 GiB memory (29%); requests 2024m CPU / 11 GiB, limits 11750m CPU / 60 GiB (limits near-capacity, requests-based scheduling leaves room).
- [observation] Consequence: CPU-only inference via llama.cpp GGUF; MoE models with small active-parameter counts are the only usable speed class; dense models above ~14B are too slow for chat.
- [open] Disk capacity not yet measured — the 50 Gi model PVC (local-hostpath) plus the 19 GB weights plus VolSync snapshot pressure need a measured free-space baseline on k8s-cp0 before the wave starts (read-only `just k8s` recipes suffice).

## Research findings

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

## Decisions (owner-ratified 2026-10-11)

- [decision] MVP scope — two apps in one wave (llama-cpp + open-webui); LiteLLM dropped (see below).
- [decision] No cloud fallback — purely local; no AI API key leaves the house.
- [decision] Model always resident in memory (~20 GB); no idle-unload.
- [decision] llama-cpp must NOT receive the kubernetes/components/zeroscaler component (HPA scale-to-zero) — the always-resident guarantee excludes idle-downscaling; recorded so a future cleanup cannot silently break it.
- [decision] New app group kubernetes/apps/ai/ with a dedicated ai namespace.
- [decision] llama.cpp server Deployment chosen over LLMKube operator for the chat model (single model = no operator machinery; LLMKube revisit trigger — multi-model orchestration, multi-runtime, or inference-metric HPA).
- [decision] Model PVC excluded from VolSync (regenerable); open-webui chat-history PVC included.
- [decision] Chat model (owner decision 2026-10-11, supersedes Qwen3-30B-A3B-Instruct-2507): Qwen3.6-35B-A3B UD-Q4_K_XL provisional, confirmed or replaced by Gemma 4 26B-A4B through the bake-off gate (Plan step 4). Qwen3-30B-A3B-2507 is fallback only.
- [decision] Bake-off pick (owner decision 2026-10-12): Qwen3.6-35B-A3B UD-Q4_K_XL, served without MTP, 2 slots. Both candidates cleared tool calling and scored equal on the paperless/sure-shaped synthetic sets; Qwen won decode (7.2-8.1 vs 7.1-7.5 tok/s) and prefill (251 s vs 322 s on a ~9k prompt); Hungarian free-text quality was too noisy on a 10-prompt sample to separate them (Gemma steadier at spelling, Qwen at single-answer instruction following). Real-data validation of the paperless/sure sets follows before Plan step 5. Full numbers: docs/progress/local-ai-stack.
- [decision] Target consumers (owner direction 2026-10-11): Open WebUI first; paperless-gpt and sure are wired to the llama-cpp endpoint in follow-up PRs once the bake-off gate passes.
- [decision] LiteLLM dropped from the MVP (owner decision 2026-10-11) — one local backend, no cloud fallback, no API cost to track and a single consumer make the gateway (and the Postgres it needs for virtual keys / spend logs) speculative; llama.cpp server already provides the OpenAI-compatible API, API-key auth and --metrics. Revisit trigger — a second backend, a cloud fallback route, or per-consumer quotas/usage accounting; per-consumer keys alone do not trigger it (llama-server accepts multiple API keys — verify on the pinned version). Consumers then repoint to the LiteLLM URL.

## Plan (one MVP wave, ordered)

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
     DDR4 dual channel; MTP speculative decoding measured slower, see docs/progress/local-ai-stack)
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

## Review findings (2026-10-11)

- [finding] GPU claim corrected — the cluster exposes an Intel iGPU via DRA (components/gpu, gpu.intel.com, used by jellyfin); no decode gain on shared DDR4, CPU path stays (see Hardware baseline).
- [finding] Model choice was a generation behind — Qwen3.5/3.6 and Gemma 4 were not evaluated; replaced by the bake-off (Plan step 4) with Qwen3.6-35B-A3B provisional.
- [finding] Throughput expectation was optimistic — 15-25 tok/s corrected to 8-15 tok/s; time-to-first-token added as a criterion.
- [finding] Double OIDC in the original plan — gateway-oidc component (Envoy-native login gate) AND Open WebUI native OAUTH_* env would mean two logins and two Pocket ID clients; one must be chosen (open question below).
- [finding] CNP cannot scope egress to an init container — Cilium identity is per pod, so the HuggingFace egress also applies to the server container; accept or use a separate download Job.
- [finding] CPU starvation risk — no CPU limit on a single node that also runs the control plane; mitigated by --threads <= 6, an explicit CPU request and a node-health check in the gate.
- [finding] Multiple consumers on one slot — Open WebUI background tasks and paperless/sure batches would queue behind chat; --parallel 2 and a disabled/pinned Open WebUI task model.
- [finding] paperless-gpt open question answered — it uses Mistral cloud (LLM + OCR); see Research findings.
- [finding] Minor — HF_TOKEN optional (models not gated); Open WebUI chart sub-components (ollama, pipelines) must be disabled.

## Open questions

- [open] Open WebUI auth model: (a) gateway-oidc component + WEBUI_AUTH_TRUSTED_EMAIL_HEADER
  (requires the header-stripping spoofing guard from the iam area), or (b) native Open WebUI
  OAuth against Pocket ID without the component. Decide before Plan step 3.
- [open] paperless-gpt OCR stays on Mistral cloud even after the LLM moves local — decide
  separately whether that is acceptable long-term.
- [open] Public exposure of Open WebUI (envoy-external + Cloudflare Tunnel + OIDC group
  ACL): deferred; decide after the MVP wave.
- [open] Embeddings/RAG plane (llmkube or TEI + memini): deferred, but sure's document
  search (vector store) is now a concrete candidate consumer — revisit when sure is wired.

## Related

- relates_to [[k8s-workloads]]
- relates_to [[iam]]
- relates_to [[external-secrets]]
- reference https://github.com/eleboucher/homelab/tree/main/kubernetes/apps/ai
- reference https://unsloth.ai/docs/models/qwen3.6
- reference https://www.jetson-ai-lab.com/models/gemma4-26b-a4b
- reference https://mintlify.wiki/we-promise/sure/hosting/ai-features
- reference https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507 (fallback)
