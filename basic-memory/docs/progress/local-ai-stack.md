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

## Real-data validation (2026-10-12, owner-approved, read-only)

Qwen3.6 (no MTP, 2 slots), temperature 0.1. Read-only exports: tools/llm-bakeoff/paperless_export.py (Django shell ORM reads) and sure_export.rb (rails runner reads); evaluation tools/llm-bakeoff/realdata.py in the open-webui pod. Nothing was written back to paperless or sure; data moved paperless/sure pod -> kubectl on the owner's laptop (memory only, plus a local result file for owner review) -> open-webui pod -> local llama-cpp. Only aggregates recorded here.

- [measured] paperless, 15 most recent documents vs their current metadata (mostly set by paperless-gpt + Mistral, possibly hand-corrected): valid JSON 15/15, correspondent 12/15 (picked from 81), document type 14/15 (from 17), created date 11/15, tags recall 0.97 / precision 0.56 (over-tags: ~3 per doc vs 1.7 current), ~50 s per document (max 91 s) with the choice lists cached as system prompt
- [measured] sure, all 41 categorised transactions (only 4 distinct categories; model saw name, merchant, amount and the flat 70-category list): 22/41 correct. Error pattern: takeaway food split across other categories, parking -> sibling car/other categories, groceries -> other costs
- [measured] multi-step tool calling (synthetic, 2 tools): list_accounts -> get_transactions(acc-1, 2026-10) -> correct sum
- [conclusion] paperless-gpt LLM part is viable on the local model; its tag prompt needs to restrain over-tagging; created-date mismatches need owner review (issue vs performance date ambiguity)
- [conclusion] sure chat assistant (tool calling, read-only answers) is viable; sure AI auto-categorisation is NOT recommended at 54% — it writes categories onto transactions
- [caveat] Small samples; sure sample covers only 4 categories; the paperless baseline is not a pure Mistral output

## Consumers wired (2026-10-12, Plan step 5, owner decision "wire everywhere, then see")

- [done] e71166b70: per-consumer keys paperless_gpt_api_key + sure_api_key added to 1Password HomeOps/llama-cpp; LLAMA_API_KEY now lists open-webui, metrics, paperless-gpt, sure; llama-cpp CNP ingress from selfhosted paperless-gpt and sure
- [done] paperless-gpt: LLM_PROVIDER openai + LLM_MODEL qwen3.6-35b-a3b + OPENAI_BASE_URL http://llama-cpp.ai.svc.cluster.local:8080/v1 (honoured for non-Azure openai, paperless-gpt main.go:1224); OPENAI_API_KEY via its ExternalSecret; OCR stays mistral_ocr; CNP egress to ai/llama-cpp:8080 added (Mistral egress kept for OCR)
- [done] sure: OPENAI_ACCESS_TOKEN / OPENAI_URI_BASE (with /v1, per sure docs) / OPENAI_MODEL in sure-secret so server and worker share the provider; CNP egress to ai/llama-cpp:8080. Custom provider uses Chat Completions (no Responses endpoint)
- [verified] sure-server: Provider::Registry.preferred_llm_provider = Custom OpenAI-compatible (llama-cpp); GET /v1/models with sure's key -> 200 qwen3.6-35b-a3b. No live sure chat was triggered (it would write LLM usage rows)
- [verified] paperless-gpt restarted cleanly (OCR mistral_ocr valid, workers up); end-to-end needs one document tagged AI-processing (owner action — it writes metadata)
- [observation] sure AI categorisation / merchant detection only run through user-created Rules (Rule::ActionExecutor::AutoCategorize / AutoDetectMerchants are the only callers) and only touch enrichable (unlocked) categories — wiring alone writes nothing
- [observation] Backups before wiring: paperless + paperless-gpt VolSync 2026-10-12 ~05:02 UTC successful; sure DB covered by the database/postgres-backup CronJob (daily 00:17)
- [risk] Real-data validation predicted paperless over-tagging (precision 0.56) and weak sure categorisation (22/41); the paperless-gpt tag prompt lives in its PVC (/app/prompts, editable in its UI), not in git

## Sure tuning for the local model (2026-10-12)

- [fixed] 7a06ad612 OPENAI_REQUEST_TIMEOUT=600: first chat died with Net::ReadTimeout at the 60 s default (Provider::Openai::DEFAULT_REQUEST_TIMEOUT); the client-wide option also covers categorisation and merchant detection
- [fixed] 5b18da83b AI_RESPONSE_TIMEOUT=600: the browser watchdog (Chat::DEFAULT_RESPONSE_TIMEOUT 90 s) POSTed report_timeout and marked the reply dead while the worker finished it at 194 s
- [fixed] 6845099fa LLM_CONTEXT_WINDOW=16384: sure sized AI batches against a 2048-token default (Assistant::TokenBudget::DEFAULT_CONTEXT_WINDOW); max 25 items per call
- [fixed] 66b29dcd6 LLM_CONTEXT_WINDOW=10240 (superseding 16384): sure estimates tokens as chars/4 x safety factor, which undercounts Hungarian text and JSON tool results; at 16384 a two-turn chat with transaction tool results reached the 16384-token slot (reply truncated, then HTTP 400 "request (16399 tokens) exceeds the available context size"). 10240 leaves ~35% headroom for estimator error and the reply
- [measured] sure chat turns with tool results took 270-350 s each (prefill 7.9-8k uncached tokens at 27-30 tok/s); this is the realistic pace for sure chat on this node
- [measured] sure chat prompt = 8372 tokens (system prompt + function tool schemas); cold prefill ~176 s at ~36 tok/s; completion ~6 tok/s. Prefix cache helps follow-ups only while the slot keeps it
- [note] All four live in sure-secret (shared by server and worker), verified in the worker: ctx=16384 items=25 http=600s watchdog=600s

## Sure chat assessment + categorisation trial (2026-10-12)

- [measured] After the timeout/context fixes the sure chat no longer fails, but turns take 150-350 s and quality is uneven: of 4 replies, one started in English, two stopped after ~7 tokens ("## ..." heading only), one was a correct Hungarian summary. Cause of the short replies not investigated (candidates: sure's max_tokens under the reduced budget, or a malformed tool call)
- [decision] Owner: try AI categorisation on uncategorised transactions instead of pursuing the chat
- [done] Trial on 25 of 88 uncategorised standard transactions (most recent by entry date), run synchronously via Family#auto_categorize_transactions in sure-server: 136 s; 19 categorised (Bayes 13, local LLM 6), 6 withheld as low-confidence (left blank, unlocked); only the 6 AI decisions are locked. Pre-run snapshot (ids, category_id, locked_attributes) kept on the owner's laptop for a revert
- [observation] Sure's BayesCategorizer runs before the LLM and learns from the family's existing categorised transactions; it handled half of the trial with no LLM call
- [next] Owner reviews the 19 in sure; then either run the remaining ~63 or revert the trial (set category_id nil + unlock for the snapshot ids)

## Next
- [next] Owner: tag one paperless document AI-processing and review the result; watch paperless-gpt logs for LLM errors/timeouts (~50 s per document expected)
- [next] If over-tagging shows up: tighten the paperless-gpt tag prompt (UI / PVC prompts), then consider moving prompts into git
- [next] sure: try the chat assistant; create an AI auto-categorise rule only if the quality is acceptable (22/41 on real data)
- [next] Consider progressDeadlineSeconds / download Job split if model switches remain frequent
- [next] Roadmap closure once consumers are judged: merge roadmap into this note per repo convention

## Relations

- implements [[local-ai-stack]]
