# Developer runbook: MSI reference inference profile

This runbook explains how another developer can operate and reproduce the local inference profile validated on 2026-10-03. It is a hardware-specific development reference, not a general production deployment guide.

Repository: [NiiOsa1/llm-inference-service](https://github.com/NiiOsa1/llm-inference-service)

Read [the qualification report](msi-inference-qualification.md) for the measured hardware, exact model labels, runtime identity, benchmark results and limitations.

Commands in this guide run in Bash inside Linux or WSL2, not Windows PowerShell. Run each command block only when its stated conditions apply.

## Prerequisites

The reference environment uses Windows with WSL2, an RTX 5090 Laptop GPU with approximately 24 GiB VRAM, Docker with NVIDIA CDI GPU access, and an approved local NVFP4 model artifact. Use the report's software and hardware inventory when assessing compatibility. Other environments require their own validation.

Before starting, provide:

- Git, Bash, Docker, Python 3 and curl in the environment where these commands run.
- A working NVIDIA driver and Docker GPU access using `nvidia.com/gpu=all`.
- The approved model directory, supplied separately from this public repository.
- The corresponding local Docker image. The recorded image ID is not a registry address and cannot be fetched with `docker pull`.
- Sufficient free GPU memory and an available host port 8000.

A Git clone supplies source files, not model weights, Docker images or runtime cache contents. Model distribution and image acquisition are separate prerequisites; this checkpoint does not provide a complete artifact distribution workflow.

## Obtain the source

For a new checkout, run these commands from a directory where you keep projects:

```bash
git clone https://github.com/NiiOsa1/llm-inference-service.git
cd llm-inference-service
```

If the repository is already cloned, open a terminal in that checkout instead. All relative paths below are resolved from the repository root. The selected launcher must be present in the checked-out revision:

```bash
ls -l scripts/start-graphs-12k-fixed-cache.sh
```

If it is absent, the checkout does not include this qualification profile. Do not substitute a similarly named experimental launcher.

## Adapt the reference launcher

The recorded launcher contains machine-specific variables. Before its first use on a different machine, set these variables in `scripts/start-graphs-12k-fixed-cache.sh`:

| Variable | What the developer supplies |
|---|---|
| `model_dir` | Absolute path to the approved model directory on that host. |
| `image_id` | Verified local image ID for the intended runtime artifact. |
| `container_name` | Container name; this runbook assumes `llm-qualification`. |
| `cache_volume` | Docker cache volume name; this runbook assumes `llm-qualification-cache`. |

These are shell variables inside the current launcher, not documented environment-variable overrides. Merely exporting a different value will not override its hardcoded assignments. Preserve the model and runtime identity when reproducing the benchmark; changing either requires requalification.

Check Docker and GPU visibility, then create the named cache volume if needed:

```bash
docker info >/dev/null
nvidia-smi
docker volume create llm-qualification-cache
```

`nvidia-smi` verifies host GPU visibility. It does not by itself verify GPU access inside a container. The launcher checks for the model directory, local image and volume before creating the container.

## Current profile

- Container: `llm-qualification`.
- Launcher: `scripts/start-graphs-12k-fixed-cache.sh`.
- Context: 12,288 tokens, including input and output.
- KV budget: 805,306,368 bytes, exactly 768 MiB.
- CUDA Graph mode: `FULL_DECODE_ONLY`, capture size 1.
- Model compilation: disabled (`-cc.mode=0`).
- One active sequence; text-only; thinking disabled in benchmark requests.
- Host endpoint: `http://127.0.0.1:8000`.

The key launcher arguments are shown below as a reference excerpt, not a standalone shell command:

```text
--max-model-len 12288
--kv-cache-dtype fp8_e4m3
--kv-cache-memory 805306368
--max-num-seqs 1
-cc.mode=0
-cc.cudagraph_mode=FULL_DECODE_ONLY
-cc.cudagraph_capture_sizes=[1]
-cc.max_cudagraph_capture_size=1
```

The explicit KV cache value controls the cache allocation budget, not total GPU memory. Startup logs report that it overrides automatic KV sizing based on `--gpu-memory-utilization`, which remains set to `0.94` in the recorded launcher. CUDA Graph replay is enabled separately from compilation. The profile must not include `--enforce-eager`, which disabled graphs in the eager reference.

## First launch

If `llm-qualification` does not already exist, run the selected launcher from the repository root:

```bash
bash scripts/start-graphs-12k-fixed-cache.sh
```

The launcher refuses to replace an existing container. A successful creation message means the container was created; model readiness must be checked separately.

## Confirm readiness

Inspect the actual arguments and follow startup logs:

```bash
docker inspect llm-qualification \
  --format 'Status={{.State.Status}} Arguments={{json .Config.Cmd}}'
docker logs --follow --tail 30 llm-qualification
```

Wait for `Application startup complete`, then press Ctrl+C to leave the log viewer. This does not stop the detached container. Check the HTTP health endpoint:

```bash
curl --silent --show-error --fail --max-time 10 \
  --write-out '\nHTTP status: %{http_code}\n' \
  http://127.0.0.1:8000/health
```

Expected result: HTTP 200. If the container exits or readiness fails, use the diagnosis section below. A health response alone does not verify answer correctness.

## Start, stop and restart an existing container

Choose the operation that matches the intended action:

| Operation | Effect |
|---|---|
| Start | Starts an existing stopped container with its saved configuration. |
| Stop | Stops the service while retaining the container. |
| Restart | Interrupts the service and starts it again with its saved configuration. |

Start:

```bash
docker start llm-qualification
```

Stop:

```bash
docker stop --timeout 120 llm-qualification
```

Restart:

```bash
docker restart --timeout 120 llm-qualification
```

After starting or restarting, repeat the readiness check. Editing a launch script does not change an existing container's saved arguments; applying different arguments requires creating a new container. Preserve the existing configuration before replacing it.

## Minimal response check

This Python example uses only the standard library. Run it after the health check succeeds. Expected output content is `READY` with a `stop` finish reason; the script prints the actual response for inspection.

```bash
python3 - <<'PY'
import json
import time
from urllib.request import Request, urlopen

payload = {
    "model": "qwen3.8-27b-nvfp4",
    "messages": [{"role": "user", "content": "Reply with exactly: READY"}],
    "temperature": 0,
    "max_tokens": 16,
    "chat_template_kwargs": {"enable_thinking": False},
}
request = Request(
    "http://127.0.0.1:8000/v1/chat/completions",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
started = time.perf_counter()
with urlopen(request, timeout=120) as response:
    status = response.status
    result = json.load(response)
choice = result["choices"][0]
print(json.dumps({
    "http_status": status,
    "seconds": round(time.perf_counter() - started, 3),
    "content": choice["message"].get("content"),
    "finish_reason": choice.get("finish_reason"),
}, indent=2))
PY
```

Streaming is requested with `"stream": true` and requires consuming the streamed events. The command above intentionally reads one complete response. An application must consume and forward streamed events to its user interface; enabling server support does not automatically make an existing full-response client stream.

## Diagnose startup failure

Filter only the latest start so old failures do not get mistaken for current failures:

```bash
started_at="$(docker inspect --format '{{.State.StartedAt}}' llm-qualification)"
docker logs --since "$started_at" llm-qualification 2>&1 \
  | grep -Ei 'ValueError|OutOfMemory|out of memory|KV cache|Graph capturing|Application startup'
nvidia-smi --query-gpu=memory.total,memory.used,memory.free,utilization.gpu --format=csv
```

Keep the first specific error, not only the final `Engine core initialization failed` wrapper. Check actual arguments, initial free GPU memory, and competing GPU workloads before changing context or cache settings. Fixed cache bypasses automatic sizing and can still fail if available memory changes. Do not increase allocations solely from an idle-memory snapshot.

## Deployment assumptions

The launcher pins a local Docker image ID and a machine-specific approved-model path. Another developer needs the corresponding image and model artifacts, a compatible NVIDIA driver and CDI setup, the named cache volume, and an adapted model path. A Git clone does not contain model weights or the Docker image.

The model is mounted read-only at `/models/qwen`; the cache volume is `llm-qualification-cache`. Hugging Face offline mode is enabled. The host port is bound to loopback. Docker shared memory is 2 GiB; local logs rotate at 10 MiB with three files; restart policy is `no`.

The module entry point currently used by the launcher emits a deprecation warning. Migrate it separately and revalidate, rather than changing it during this checkpoint.

## Preserve reproducibility

Version the selected launcher, synthetic benchmark requests, expected answers and measured results. Record the model manifest, image identity, driver and hardware alongside each new qualification. Raw container inspection includes environment values and should be reviewed before publication. Runtime logs match the repository's `*.log` ignore rule, so evidence logs require deliberate inclusion or a separate archive.

Git does not preserve untracked files, ignored logs, model weights, Docker images or named volumes. Back up or distribute those artifacts separately, with their identities recorded.

## Alternative profiles

The eager 25,088-token reference uses `scripts/start-tools-25088.sh` when that experimental script is included in the checkout. It trades the measured graph speed advantage for a larger tested context. It is not the selected daily-development default.

Do not run both model profiles simultaneously on the reference GPU. To switch, inspect and preserve the existing container, stop it, and create or start the intended alternative. Experimental launcher names describe trials, including failed ones; their presence does not establish that they work.

## Acceptance and deployment boundary

A successful launch, health response and short response check establish basic operation. Reproduction of the qualification additionally requires replaying the saved synthetic requests, checking exact expected answers and testing restart recovery. Consult the qualification report for which checks passed and which remain untested.

The recorded restart policy is `no`, the API is loopback-bound, and one sequence is scheduled at a time. Remote access controls, application queue limits, cancellation, long-duration stability and host reboot recovery remain separate deployment work. Reassess the memory budget and repeat the relevant tests on different hardware instead of treating the reference values as universal defaults.
