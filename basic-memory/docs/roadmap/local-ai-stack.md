---
title: local-ai-stack
type: roadmap
permalink: home-ops/docs/roadmap/local-ai-stack
topic: Self-hosted LLM inference stack in a new ai namespace - llama.cpp server (Qwen3-30B-A3B-Instruct-2507
  Q4_K_M, CPU-only), LiteLLM as the unified OpenAI-compatible gateway, and Open WebUI
  behind Pocket ID OIDC - no cloud fallback, model always resident
status: planned
priority: medium
scope: One new app group kubernetes/apps/ai/ with namespace ai and three apps in one
  MVP wave - llama-cpp (bjw-s app-template HelmRelease, HF download init container,
  model PVC without VolSync, envoy-internal HTTPRoute), litellm (official chart, ServiceMonitor
  + Grafana dashboard, ESO admin key), open-webui (official chart, gateway-oidc component
  + Pocket ID client, VolSync on chat-history PVC). LLMKube operator deliberately
  not used for the chat model.
rationale: The node has no GPU and 45 GiB actually free RAM at ~6% CPU - a Q4-quantized
  MoE model with 3.3B active parameters is the only class that delivers usable Hungarian
  chat on CPU (20-40 tok/s). Qwen3-30B-A3B-Instruct-2507 is the only candidate combining
  that speed class with credible multilingual/Hungarian coverage; every measured Hungarian
  alternative is either too large for RAM (GLM-4.5-Air Q4 = 73.5 GB), too slow when
  dense (Gemma 3 27B, Llama 3.3 70B), or weak in multilingual (gpt-oss-20b). Hungarian-adapted
  models (PULI, Racka-4B) are not competitive with international base models on generative
  tasks per the independent "Made in Hungary" re-evaluation.
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
- Qwen3-30B-A3B-Instruct-2507 Q4_K_M as chat model (chosen - MoE 3.3B active params,
  ~19 GB weights, Apache-2.0, 100+ languages, 2507 revision improves long-tail language
  coverage; no published Hungarian benchmark, so a Hungarian validation prompt set
  is an MVP acceptance criterion)
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
- Cloud fallback model behind LiteLLM (rejected by owner decision 2026-10-11 - purely
  local stack, no AI API key leaves the house; the LiteLLM config keeps the structure
  open for a later fallback route)
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
- litellm
- open-webui
- qwen3
- hungarian
---

# Local AI stack — llama.cpp + LiteLLM + Open WebUI in `ai` namespace

Self-hosted, purely local LLM stack on the existing single Talos node (HP ProDesk 600 G6,
16 vCPU, 64 GiB RAM, NO GPU): a llama.cpp server hosting a CPU-friendly Hungarian-capable
chat model, LiteLLM as the single OpenAI-compatible gateway, and Open WebUI as the chat
frontend behind Pocket ID OIDC. Reference architecture: eleboucher/homelab
kubernetes/apps/ai (llama-cpp + litellm + litellm-operator + open-webui + memini +
llmkube-for-embeddings), adapted to this repo's canonical app shape.

## Metadata (observation-form)

- [topic] Local AI inference stack — llama.cpp (Qwen3-30B-A3B-Instruct-2507 Q4_K_M) + LiteLLM gateway + Open WebUI, new ai namespace, no cloud fallback
- [status] planned
- [priority] medium
- [area] k8s-workloads / networking / iam / external-secrets / observability
- [created] 2026-10-11
- [effort] M — one new app group with three apps in one MVP wave, all riding existing planes (app-template pattern, ESO/onepassword-connect, envoy-internal HTTPRoute, gateway-oidc component, ServiceMonitor/Prometheus)

## Hardware baseline (measured 2026-10-11, live cluster)

- [observation] Single node k8s-cp0: 16 vCPU, 64 GiB RAM, no GPU (no nvidia.com/gpu in node capacity); i7-class desktop CPU with DDR4 dual-channel (~40 GB/s memory bandwidth).
- [observation] Actual usage at measurement: 998m CPU (6%), 18.3 GiB memory (29%); requests 2024m CPU / 11 GiB, limits 11750m CPU / 60 GiB (limits near-capacity, requests-based scheduling leaves room).
- [observation] Consequence: CPU-only inference via llama.cpp GGUF; MoE models with small active-parameter counts are the only usable speed class; dense models above ~14B are too slow for chat.

## Research findings

- [observation] Hungarian LLM landscape 2026: the independent re-evaluation "Made in Hungary" (arXiv 2609.18284) found data contamination in PULI/OTP evaluations and showed international base models (Qwen3, Llama 3.1) match or beat the Hungarian-adapted models (PULI-LlumiX, Racka-4B) on most generative tasks; adapted models win only on spelling/grammar-style linguistic tasks.
- [observation] Qwen3-30B-A3B-Instruct-2507: 30.5B total / 3.3B active MoE, Q4_K_M GGUF ~19 GB, Apache-2.0, official claim 100+ languages, 2507 revision targets long-tail language knowledge; no published Hungarian benchmark (validation prompt set required — see acceptance criteria).
- [observation] Gemma 3 27B: only fitting model with measured Hungarian scores (HuGME — HuMMLU 68.86, HuTruthfulQA 67.07 — beats PULI family and SambaLingo 70B, approaches Llama-3.3-70B) but dense-27B on this CPU is ~3-5 tok/s; weak spelling (50.00). Deferred as a possible second model for quality-critical batch tasks.
- [observation] GLM-4.5-Air (106B MoE, 12B active, MIT): Q4_K_M GGUF 73.5 GB (bartowski) — does not fit; IQ2_M 45.12 GB is borderline and degraded; no Hungarian measurements published.
- [observation] gpt-oss-20b: official MMMLU covers 14 languages, Hungarian absent; independent evaluation (arXiv 2508.12461) found multilingual weakness; community Hungarian LoRA (csokosgeza/gpt-oss-20b-hun-4bit) exists to patch the gap — base model unsuitable for Hungarian out of the box.
- [observation] Racka-4B (elte-nlp): Hungarian-adapted Qwen3-4B, CC-BY-NC-SA gated research license, explicitly unaligned/unsafe for end users; GGUF available (Q4_K_M 2.5 GB) — not chosen; a future edge-model niche is not excluded if a concrete consumer appears.
- [observation] Reference architecture (eleboucher/homelab, kubernetes/apps/ai): chat model served by a plain llama.cpp server Deployment (bjw-s app-template — uv+huggingface_hub init container downloads GGUF to a PVC, ghcr.io/ggml-org/llama.cpp server, /health probes, LLAMA_API_KEY from secret); LLMKube operator kept ONLY for embedding+reranker models; LiteLLM as unified proxy with Grafana dashboard and ServiceMonitor; open-webui as frontend; memini as agent memory. Their llama-cpp uses a Vulkan build with /dev/dri hostPath (they have a GPU) — this cluster needs the plain CPU server image instead.

## Decisions (owner-ratified 2026-10-11)

- [decision] MVP scope — all three apps in one wave (llama-cpp + litellm + open-webui).
- [decision] No cloud fallback behind LiteLLM — purely local; no AI API key leaves the house.
- [decision] Model always resident in memory (~20 GB); no idle-unload.
- [decision] New app group kubernetes/apps/ai/ with a dedicated ai namespace.
- [decision] llama.cpp server Deployment chosen over LLMKube operator for the chat model (single model = no operator machinery; LLMKube revisit trigger — multi-model orchestration, multi-runtime, or inference-metric HPA).
- [decision] Model PVC excluded from VolSync (regenerable); open-webui chat-history PVC included.

## Plan (one MVP wave, ordered)

1. Group scaffolding: kubernetes/apps/ai/ (namespace.yaml, kustomization.yaml, per-app
   ks.yaml + app/ shape, cluster-root ks.yaml registration).
2. llama-cpp app: app-template HelmRelease, CPU llama.cpp server image (digest-pinned),
   uv + huggingface_hub init container downloading Qwen3-30B-A3B-Instruct-2507 Q4_K_M
   to a local-hostpath PVC (50 Gi), -c 32768 context, flash-attn, LLAMA_API_KEY via
   ExternalSecret (onepassword-connect, 12h refresh), requests ~24Gi memory (weights
   mmap-resident), no CPU limit, /health probes with generous startup budget (model load),
   CiliumNetworkPolicy (egress to huggingface.co for the init container only, ingress
   in-cluster), envoy-internal HTTPRoute for LAN testing.
3. litellm app: official Helm chart (no operator — YAGNI), config with a single primary
   backend (llama-cpp Service), admin key via ESO, ServiceMonitor into existing
   Prometheus, Grafana dashboard, envoy-internal HTTPRoute (LAN API surface).
4. open-webui app: official Helm chart, gateway-oidc component + Pocket ID client
   (per-app group ACL pattern), VolSync component on the chat-history PVC,
   envoy-internal exposure first (public exposure is a separate later decision).
5. Validation gate (acceptance criteria, run on the live stack):
   - Hungarian prompt set (10-15 prompts — spelling correction, register rewrite,
     Hungarian summarization, factual Hungarian QA) judged subjectively acceptable.
   - Measured throughput in a chat session at 32k context — target >= 10 tok/s sustained
     (expectation 20-40 tok/s; prompt processing lower).
   - LiteLLM proxy answers /v1/models and routes a completion to the local backend;
     metrics visible in Grafana.
   - Open WebUI login via Pocket ID works; a chat round-trip completes.

## Open questions

- [open] paperless-gpt backend: verify whether it currently calls a cloud API — if so,
  it is the first concrete external consumer of the LiteLLM endpoint (candidate for a
  separate small roadmap item).
- [open] Public exposure of Open WebUI (envoy-external + Cloudflare Tunnel + OIDC group
  ACL): deferred; decide after the MVP wave.
- [open] Embeddings/RAG plane (llmkube or TEI + memini): deferred until a concrete
  consumer exists (YAGNI).

## Related

- relates_to [[k8s-workloads]]
- relates_to [[iam]]
- relates_to [[external-secrets]]
- reference https://github.com/eleboucher/homelab/tree/main/kubernetes/apps/ai
- reference https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507
