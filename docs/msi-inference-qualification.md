# MSI inference qualification: findings and decision

Recorded 2026-10-03. Status: local development validation, not production certification.

## Decision

Use the **12,288-token CUDA Graph profile with a fixed 768 MiB KV cache** for daily development on the tested MSI environment. Keep the eager 25,088-token profile as a capacity reference and optional larger-context alternative. The latter has passed a long-input test, but is not a universal model or hardware limit.

CUDA Graph replay and model compilation are separate controls. The selected profile enables decode graph replay and leaves `torch.compile` disabled. It serves one active sequence at a time.

The selected configuration passed three saved near-limit requests and two container restart checks, each followed by a correct near-limit response. This resolves the immediate development blocker. Further parameter sweeps are deferred unless a concrete workload requires them.

## Test environment

| Component | Observed value |
|---|---|
| Laptop | MSI Titan 18 HX Dragon Edition Norse Myth A2XWJG |
| CPU | Intel Core Ultra 9 285HX, 24 cores, 24 logical processors |
| Installed RAM | 96 GiB from DIMM capacities; Windows reported 95.42 GiB total physical memory |
| GPU | NVIDIA GeForce RTX 5090 Laptop GPU |
| Reported GPU memory | 24,463 MiB, approximately 23.89 GiB |
| Reported GPU power cap | 150 W |
| Host runtime | Windows with WSL2; Ubuntu 24.04 environment |
| Driver report | NVIDIA-SMI 610.53, KMD 610.74, CUDA UMD 13.3 |
| Container base | CUDA 13.2.1 development image, Ubuntu 24.04 |
| Python / uv | 3.12.3 / 0.12.18 |
| Inference engine | vLLM 0.30.0; response fingerprint `vllm-0.30.0-6729e16d` |

The driver-reported CUDA version and the container CUDA toolkit version describe different parts of the stack.

### Model and image identity

- Served API name: `qwen3.8-27b-nvfp4`.
- Approved local artifact directory: `nvidia--Qwen3.8-27B-NVFP4-482ca0f3`.
- Observed architecture: `Qwen3_5ForConditionalGeneration`; runtime uses hybrid attention and state-space components.
- Quantization reported by the engine: `modelopt_mixed`, for the approved NVFP4 artifact.
- Local Docker image ID: `sha256:30d6740bb68a752427a4156a36f1a98db5279f9006c4e7c33882cb250e2c53a0`.

Model Control metadata subsequently inspected on 2026-10-03 records repository `nvidia/Qwen3.8-27B-NVFP4` and full revision `482ca0f3832238542f8f5295dde86b5f22711d80`. Its historical integrity record reports 19 files verified and promotion to `SUPPLY_CHAIN_APPROVED_FOR_TESTING` on 2026-09-26. This is recorded local provenance, not independent upstream verification, a fresh integrity check or production certification.

The original checksum list is preserved at [model-reference/SHA256SUMS](model-reference/SHA256SUMS); the copied list was compared byte for byte with the original. The complete local `modelctl.json` has not been published with this report. The API alias is a serving label, not proof of model identity. A local image ID is not a published registry pull reference. See the developer runbook for acquisition and verification instructions.

## Selected parameters and what they do

| Setting | Purpose and boundary |
|---|---|
| `--max-model-len 12288` | Combined context budget for input and generated output, including chat formatting and tool definitions. |
| `--kv-cache-memory 805306368` | Explicit KV cache allocation budget: 768 MiB or 0.75 GiB. Overrides automatic KV sizing; not a cap on total GPU memory. |
| `--gpu-memory-utilization 0.94` | Retained in the launcher; startup explicitly reports that manual KV allocation bypasses this setting for KV sizing. |
| `--kv-cache-dtype fp8_e4m3` | Stores the attention KV cache in FP8 to reduce memory requirements. |
| `--max-num-seqs 1` | Limits active scheduled sequences; does not by itself define an application queue or admission policy. |
| `--enable-chunked-prefill` | Allows prompt processing to be scheduled in chunks. |
| `--language-model-only` | Selects text-only operation for this deployment. |
| `-cc.mode=0` | Leaves model compilation disabled. |
| `-cc.cudagraph_mode=FULL_DECODE_ONLY` | Replays captured GPU work during supported decoding steps, reducing launch overhead. |
| `-cc.cudagraph_capture_sizes='[1]'` | Captures the single-sequence decode shape used here. |
| `-cc.max_cudagraph_capture_size=1` | Bounds capture size for this profile. |
| `--reasoning-parser qwen3` | Configures reasoning output parsing; it does not itself enable or disable model thinking. |
| `--enable-auto-tool-choice` and `--tool-call-parser qwen3_xml` | Enable automatic tool-request generation and parsing. Application code must execute approved tools. |
| Request `chat_template_kwargs.enable_thinking=false` | Disables thinking for the measured requests. |

`--enforce-eager` is absent from the selected profile. Earlier eager profiles used it to disable model compilation and CUDA Graph execution.

## Benchmark method

Tests used local HTTP requests, synthetic site IDs and CTN values, temperature zero, and thinking disabled. No private telecom dataset was used for these published cases. Requests were sequential. Streaming tests used Python's standard-library HTTP client; HTTPX is not required for streaming support.

For the varied-input comparison, the graph run saved each complete request and expected answer. The eager run replayed those saved requests. Validation parsed the model's plain JSON answer and compared it with the exact expected object, including leading zeros, site-to-CTN associations, the synthetic label, and null connecting ports. These were prompt-requested JSON responses, not proof of schema-constrained generation.

Equal round counts alone do not establish a fair benchmark. Prompt contents, token counts, output length, sampling, cache state, background load, and warmup also matter. These small sequential experiments support a local profile decision, not general throughput or percentile claims.

### Same context limit: streaming at 12,288 tokens

Each request used 84 prompt tokens and produced 46 completion tokens.

| Run | Graph first visible text (s) | Eager first visible text (s) | Graph total (s) | Eager total (s) |
|---|---:|---:|---:|---:|
| 1 | 0.375 | 0.289 | 1.734 | 4.831 |
| 2 | 0.145 | 0.220 | 1.566 | 4.608 |
| 3 | 0.149 | 0.219 | 1.568 | 4.601 |

All streams completed with the expected answer and stop reason. For repeat runs 2 and 3, mean total time was 1.567 seconds with graphs versus 4.605 seconds eager, approximately 2.94 times faster. First visible text was not faster for graphs in every run. Streaming exposes partial output sooner; it is not itself evidence of faster model computation.

### Practical profiles: graphs 12,288 versus eager 25,088

| Run | Records | Prompt tokens | Graph output tokens | Eager output tokens | Graph seconds | Eager seconds | Exact answer |
|---|---:|---:|---:|---:|---:|---:|---|
| 1 | 20 | 588 | 89 | 89 | 3.077 | 8.721 | Both pass |
| 2 | 490 | 11868 | 141 | 141 | 9.826 | 16.416 | Both pass |
| 3 | 20 | 588 | 141 | 141 | 4.501 | 13.400 | Both pass |
| 4 | 490 | 11868 | 141 | 141 | 9.805 | 16.410 | Both pass |
| 5 | 20 | 588 | 89 | 89 | 2.885 | 8.820 | Both pass |
| 6 | 490 | 11868 | 89 | 141 | 8.243 | 16.835 | Both pass |

Graphs were faster in all six observations. Runs 1–5 matched input and output token counts. Run 6 produced different JSON whitespace and output lengths, so its time ratio is not an equal-output speed comparison. This comparison changes both execution mode and configured context limit. The matched-12K experiment above better isolates execution mode.

These graph measurements preceded the switch to fixed KV allocation. The fixed-cache replays below checked that the selected profile retained the observed behavior.

### Fixed-cache validation

| Check | Prompt tokens | Completion tokens | Request seconds | Result |
|---|---:|---:|---:|---|
| Saved varied request 2 | 11868 | 141 | 9.856 | Exact JSON pass |
| Saved varied request 4 | 11868 | 141 | 9.775 | Exact JSON pass |
| Saved varied request 6 | 11868 | 89 | 8.221 | Exact JSON pass |
| Restart 1, saved request 2 | 11868 | Recorded in raw result | 9.987 | Exact JSON pass |
| Restart 2, saved request 2 | 11868 | Recorded in raw result | 9.850 | Exact JSON pass |

All returned HTTP 200. Readiness waits after the restart command were 45.841 and 35.727 seconds. These exclude time spent inside the blocking restart command and include polling granularity; they are not precise total cold-start times.

Startup reported a 0.75 GiB explicit cache, capacity of 13,165 cache tokens, and a 12,288-token configured request limit. The capacity estimate is not an API context limit or permission to serve multiple active sequences. GPU snapshots showed 1,911 MiB free after startup and 1,547 MiB free after the three replays. These snapshots do not measure minimum free memory during execution.

### Tools and larger-context reference

Before fixed-cache selection, graphs at 12K produced three valid `get_current_ctn` requests with `site_id="0481"` in 1.265, 1.159 and 1.110 seconds. The lookup was not executed in that test. A manually supplied synthetic tool result produced a correct final answer in 1.933 seconds. Empty or null assistant content alongside a valid tool call is expected at the request stage.

Eager at 25,088 accepted a synthetic request with 24,564 input tokens and 114 completion tokens in 24.731 seconds. All three requested associations were correct. That is a successful long-input observation, not exhaustive correctness or reliability qualification at that limit.

## Failures and why fixed cache was selected

1. Compilation experiments with graphs disabled failed initialization because insufficient memory remained for the KV cache. This does not show that Qwen can never use compilation.
2. Eager context experiments above 25,088 and graph experiments at 13K and 14K failed cache admission under their observed memory conditions. The highest passing setting is environment-specific, not a universal model limit.
3. Graphs at 12K initially passed requests, but later failed to restart with automatic KV sizing. One failure required about 0.67 GiB but reported about 0.56 GiB available at admission, with an estimated maximum length of 7,840.
4. A temporary 7,168-token graph profile started successfully. It was a diagnostic fallback, not the final selection.
5. Selected configuration fields for the 7K and failing 12K containers differed only in context length. Logs also showed varying graph memory estimates. Installed source inspection showed automatic sizing subtracts a graph estimate and cache admission reserves additional space. The cause of the estimate variation was not conclusively established.
6. Setting an explicit 768 MiB cache bypassed automatic KV sizing. The 12K profile then passed the recorded requests and two restart checks.

Estimated graph memory and the final graph pool were different measurements: earlier logs reported estimates around 0.43–0.54 GiB and final pools around 0.04 GiB; fixed-cache startup reported capture around 0.01 GiB. These differences do not independently prove an upstream defect or establish an amount of safely reclaimable memory.

## Evidence inventory

Paths are relative to the repository. As of this documentation update on 2026-10-03, the experiment directories below remain local and untracked; they were preserved in a local backup archive and have not been published to GitHub. The published runbook and model checksum list do not include this benchmark replay evidence. Logs match the repository's `*.log` ignore rule and need intentional preservation if selected for publication.

| Local evidence directory under `qualification-records/` | Purpose |
|---|---|
| `eager-25088-20261003T032323Z` | Long-context eager checkpoint |
| `graphs-12288-20261003T042109Z` | Earlier graph checkpoint |
| `graphs-12k-varied-20261003T043203Z` | Saved six-request benchmark and expected results |
| `eager-25088-replay-20261003T043610Z` | Same-request eager replay |
| `graphs-12k-restart-20261003T044626Z` | Automatic cache restart failure evidence |
| `graphs-12k-fixed-cache-20261003T051629Z` | Three fixed-cache near-limit replays |
| `fixed-cache-restart-20261003T051858Z` | First fixed-cache restart validation |
| `fixed-cache-restart-20261003T052448Z` | Second fixed-cache restart validation |

## Limits and follow-up scope

Not yet established: long-duration stability, host reboot or GPU reset recovery, concurrent-user queue behavior, cancellation and disconnect cleanup, application-level streaming, authentication for remote exposure, production telemetry and deployment recovery policies. Tool calling and streaming were tested on the earlier graph profile; they were not separately rerun after fixed-cache selection.

Keep the selected profile for development. Requalify relevant workloads when changing the model, quantization, image, engine, driver, GPU, context, concurrency, or cache allocation. A cloud deployment gets its own hardware profile. This work provides reusable methods and evidence; it does not make every similarly sized LLM interchangeable.

See [the developer runbook](msi-development-runbook.md) for setup and operation.
