#!/usr/bin/env bash
set -euo pipefail

container_name="llm-qualification"
image_id="sha256:30d6740bb68a752427a4156a36f1a98db5279f9006c4e7c33882cb250e2c53a0"
model_dir="/home/niiosa/models/approved/nvidia--Qwen3.8-27B-NVFP4-482ca0f3"
cache_volume="llm-qualification-cache"

docker info >/dev/null

if docker container inspect "$container_name" >/dev/null 2>&1; then
  printf 'Container %s already exists. Nothing changed.\n' "$container_name"
  exit 1
fi

if [[ ! -d "$model_dir" ]]; then
  printf 'Model directory missing: %s\n' "$model_dir" >&2
  exit 1
fi

docker image inspect "$image_id" >/dev/null
docker volume inspect "$cache_volume" >/dev/null

docker run -d \
  --name "$container_name" \
  --pull=never \
  --restart=no \
  --device=nvidia.com/gpu=all \
  --publish 127.0.0.1:8000:8000 \
  --shm-size=2g \
  --log-driver=local \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  --env HF_HUB_OFFLINE=1 \
  --env VLLM_WSL2_ENABLE_PIN_MEMORY=0 \
  --env VLLM_LOGGING_LEVEL=INFO \
  --mount "type=bind,source=$model_dir,target=/models/qwen,readonly" \
  --mount "type=volume,source=$cache_volume,target=/root/.cache" \
  --entrypoint /opt/venv/bin/python \
  "$image_id" \
  -m vllm.entrypoints.openai.api_server \
  --model /models/qwen \
  --served-model-name qwen3.8-27b-nvfp4 \
  --host 0.0.0.0 \
  --port 8000 \
  --kv-cache-dtype fp8_e4m3 \
  --max-model-len 12288 \
  --gpu-memory-utilization 0.94 \
  --kv-cache-memory 805306368 \
  --max-num-seqs 1 \
  --enable-chunked-prefill \
  --language-model-only \
  -cc.mode=0 \
  -cc.cudagraph_mode=FULL_DECODE_ONLY \
  -cc.cudagraph_capture_sizes='[1]' \
  -cc.max_cudagraph_capture_size=1 \
  --reasoning-parser qwen3 \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_xml

printf 'Container created. Model startup is still pending; check readiness before use.\n'
