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

A Git clone supplies source files, not model weights, Docker images or runtime cache contents. The sections below describe building the runtime and acquiring the recorded model revision. These instructions have been reviewed, but have not yet been executed end to end on a second clean machine.

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

## Reproduction scope and source revision

Purpose: distinguish matching inputs from a claim of identical results. This guide pins the recorded model and software inputs. It does not promise byte-identical rebuilt images, identical generated output or identical timing on every machine. Driver, WSL kernel, Docker, GPU power/thermal state and available memory also matter.

The original qualification documentation and launcher were committed as `508085f`. This updated guide and its checksum file require a later commit. For repeatable use, obtain the maintainer's full commit ID containing this update and check out that revision, rather than relying indefinitely on moving `main`. Do not substitute the older commit when you need the new checksum file.

Run in Bash from the checkout to record the actual source revision and inspect local changes:

```bash
git rev-parse HEAD
git status --short
```

Retain the full commit ID and any intentional launcher edits with your test results.

## Build and inspect the runtime image

Purpose: turn the published build recipe into a local image. Run from the repository root on a new machine; an existing qualified installation does not need rebuilding merely because this document changed.

| Build input | Recorded setting / purpose |
|---|---|
| Dockerfile base | CUDA 13.2.1 development image, Ubuntu 24.04, pinned by image digest |
| uv | 0.12.18, copied from a digest-pinned image |
| Managed Python | 3.12.3 |
| pyproject.toml extra `vllm` | vLLM 0.30.0; Transformers 5.17.0; Torch 2.13.0+cu132; Torchvision 0.28.0+cu132; Torchaudio 2.11.0+cpu |
| uv.lock | Resolved Python dependency versions and distribution information |
| .dockerignore | Files excluded from the build context |

The Dockerfile runs `uv sync --locked --extra vllm --no-dev --no-editable`. This uses the lockfile, rejects stale lock data, selects the inference dependency group and excludes development dependencies. `RUN` is Dockerfile syntax, not a Bash command. Do not run installation commands on the host to reproduce the container environment.

Run in Bash:

```bash
docker build --tag llm-inference-service:msi-20261003 .
docker image inspect llm-inference-service:msi-20261003 --format '{{.Id}}'
```

`--tag` assigns a local name; the final `.` selects the current directory as the build context. Stop if the build fails. Network access and sufficient disk space are required to obtain the pinned images, Python and packages. Do not loosen version pins to bypass an unavailable dependency.

Use this metadata-only check to confirm installed versions without loading model weights:

```bash
docker run --rm --entrypoint /opt/venv/bin/python \
  llm-inference-service:msi-20261003 \
  -c 'import sys; from importlib.metadata import version; print(sys.version); print({p: version(p) for p in ["vllm", "transformers", "torch", "torchvision", "torchaudio", "huggingface-hub"]})'
```

`--rm` removes this temporary inspection container after exit. The Python imports are from the standard library. Compare the five inference package versions with the table. Record the Hugging Face Hub version too; it is used for acquisition below.

The originally tested local image ID was `sha256:30d6740bb68a752427a4156a36f1a98db5279f9006c4e7c33882cb250e2c53a0`. A rebuild can have a different ID. Never assign the original ID to a different image or claim that a new build is the exact original artifact. Exact-image reproduction requires the original saved image or a published immutable image digest, neither of which is supplied by this repository at this checkpoint.

## Acquire and verify the model

Purpose: identify and verify the actual model bytes, separately from the runtime image.

- Recorded repository: `nvidia/Qwen3.8-27B-NVFP4`.
- Recorded full revision: `482ca0f3832238542f8f5295dde86b5f22711d80`.
- Identity source: the approved local artifact's `modelctl.json`, not independent upstream verification.
- Expected fingerprints: [model-reference/SHA256SUMS](model-reference/SHA256SUMS).
- The historical record reports 19 files verified and `SUPPLY_CHAIN_APPROVED_FOR_TESTING` on 2026-09-26. This is not production certification or a fresh verification of your copy.

If you already have the approved artifact, skip downloading and use its absolute directory path in the verification step. Otherwise, the following uses the built image's Hugging Face library to download this revision. It requires upstream availability and any applicable access/license conditions. If acquisition fails, stop and resolve that issue; do not substitute `main` or a similarly named model.

Run in Bash from the repository root. Keep this terminal open for the next steps:

```bash
repo_dir="$PWD"
model_dir="$HOME/models/nvidia--Qwen3.8-27B-NVFP4-482ca0f3"
mkdir -p "$model_dir"
docker run --rm --user "$(id -u):$(id -g)" \
  --env HF_HOME=/tmp/hf-home \
  --mount "type=bind,source=$model_dir,target=/download" \
  --entrypoint /opt/venv/bin/python \
  llm-inference-service:msi-20261003 \
  -c 'from huggingface_hub import snapshot_download; snapshot_download(repo_id="nvidia/Qwen3.8-27B-NVFP4", revision="482ca0f3832238542f8f5295dde86b5f22711d80", local_dir="/download")'
```

`repo_dir` and `model_dir` are variables chosen for this guide; `$PWD` is the current directory and `$HOME` is your home directory. `--user` keeps downloaded file ownership aligned with your host user. The writable bind mount puts downloads in your chosen host folder. This acquisition container does not request GPU access. Weight shards alone total approximately 21.9 GB; allow additional space for the image, build cache and download overhead.

Before verification, set `model_dir` to the actual artifact directory if you skipped the download. Run from the repository root:

```bash
repo_dir="$PWD"
(
  cd "$model_dir" &&
  sha256sum --check "$repo_dir/docs/model-reference/SHA256SUMS"
)
```

The parentheses keep the directory change inside a subshell. `sha256sum --check` reads every listed file and compares its fingerprint with the recorded value. Expect all 19 entries to report `OK` and a zero exit status. Stop on missing files or mismatches. This reads the large weight files from disk but does not load them onto the GPU. The list checks named files, not extra files, and matching it establishes agreement with the recorded artifact rather than safety or model quality.

## Verify GPU access inside Docker

Purpose: host GPU visibility alone does not prove the container can access it. With the built image available, run:

```bash
nvidia-smi
docker run --rm --device=nvidia.com/gpu=all \
  --entrypoint nvidia-smi llm-inference-service:msi-20261003
```

Both should show the intended GPU. If the container command fails, configure the NVIDIA driver/container toolkit and CDI support for your environment before continuing. Do not change the model profile to work around missing GPU access. Record `docker version`, `uname -r` and the driver/GPU output alongside results. Consult the official [NVIDIA CDI guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html) for host setup.

## Adapt the reference launcher

The recorded launcher contains machine-specific variables. Before its first use on a different machine, set these variables in `scripts/start-graphs-12k-fixed-cache.sh`:

| Variable | What the developer supplies |
|---|---|
| `model_dir` | Absolute path to the approved model directory on that host. |
| `image_id` | Verified local image ID for the intended runtime artifact. |
| `container_name` | Container name; this runbook assumes `llm-qualification`. |
| `cache_volume` | Docker cache volume name; this runbook assumes `llm-qualification-cache`. |

Obtain your newly built image ID with:

```bash
docker image inspect llm-inference-service:msi-20261003 --format '{{.Id}}'
```

Open `scripts/start-graphs-12k-fixed-cache.sh` in your editor. Replace the quoted value assigned to `image_id` with that output, and replace the quoted `model_dir` value with your verified absolute model path. Keep the container and volume names above unless you also adapt every later command. These edits configure your local checkout; the instructions do not require changing the launcher's argument logic.

Check Bash syntax after saving, without starting the service:

```bash
bash -n scripts/start-graphs-12k-fixed-cache.sh
```

No output and exit status zero means the syntax check passed. It does not verify GPU memory or model readiness.

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

The later graph/eager qualification folders were not included in commit `508085f`; they were backed up locally. Their publication is still pending review. A clone alone therefore does not yet provide the complete benchmark replay suite. Obtain the reviewed synthetic requests, expected answers and results before claiming benchmark reproduction. Version the selected launcher, synthetic benchmark requests, expected answers and measured results. Record the model manifest, image identity, driver and hardware alongside each new qualification. Raw container inspection includes environment values and should be reviewed before publication. Runtime logs match the repository's `*.log` ignore rule, so evidence logs require deliberate inclusion or a separate archive.

Git does not preserve untracked files, ignored logs, model weights, Docker images or named volumes. Back up or distribute those artifacts separately, with their identities recorded.

## Alternative profiles

The eager 25,088-token reference is historical. Experimental launchers, including `start-tools-25088.sh`, were archived outside the working repository and are not supplied in the current `scripts/` directory. It trades the measured graph speed advantage for a larger tested context. It is not the selected daily-development default.

Do not run both model profiles simultaneously on the reference GPU. To switch, inspect and preserve the existing container, stop it, and create or start the intended alternative. Experimental launcher names describe trials, including failed ones; their presence does not establish that they work.

## Acceptance and deployment boundary

A successful launch, health response and short response check establish basic operation. Reproduction of the qualification additionally requires replaying the saved synthetic requests, checking exact expected answers and testing restart recovery. Consult the qualification report for which checks passed and which remain untested.

The recorded restart policy is `no`, the API is loopback-bound, and one sequence is scheduled at a time. Remote access controls, application queue limits, cancellation, long-duration stability and host reboot recovery remain separate deployment work. Reassess the memory budget and repeat the relevant tests on different hardware instead of treating the reference values as universal defaults.

## Validation status and references

This revision adds build, acquisition and verification instructions reviewed against official documentation. These new instructions have not been executed end to end on a second clean MSI system. The existing runtime qualification remains the evidence for the recorded 12K fixed-cache profile. Full reproducibility acceptance remains open until a clean-machine run and the complete benchmark replay are recorded.

- [Docker build and tags](https://docs.docker.com/get-started/docker-concepts/building-images/build-tag-and-publish-an-image/)
- [uv locking and syncing](https://docs.astral.sh/uv/concepts/projects/sync/)
- [Hugging Face revision-specific downloads](https://huggingface.co/docs/huggingface_hub/en/guides/download)

For a new machine, record the source commit, local launcher diff, image ID, package versions, model checksum results, host versions, health and response checks, and two restart checks. Replay the original benchmark inputs when available, including expected-answer comparisons. Do not equate a successful short response with the complete qualification.
