FROM nvidia/cuda:13.2.1-devel-ubuntu24.04@sha256:44a9504c6dfb50b1241464241b02a93871928f373de6f5a644cf5fe9f080aa63

COPY --from=ghcr.io/astral-sh/uv:0.12.18@sha256:3adc3706091ce7c2fe595e669628caedd6d951551b92b258b7e7dbe06d9440bc /uv /usr/local/bin/uv

ENV UV_PYTHON_INSTALL_DIR=/opt/python
ENV UV_PYTHON_PREFERENCE=only-managed

RUN uv python install 3.12.3 \
    && uv venv --python 3.12.3 /opt/venv \
    && /opt/venv/bin/python --version

ENV UV_PROJECT_ENVIRONMENT=/opt/venv
ENV UV_LINK_MODE=copy

WORKDIR /app

COPY pyproject.toml uv.lock .python-version README.md ./
COPY src/ ./src/

RUN uv sync --locked --extra vllm --no-dev --no-editable \
    && uv cache clean

# Make installed environment commands discoverable by subprocesses.
ENV PATH="/opt/venv/bin:$PATH"
ENTRYPOINT ["/opt/venv/bin/python"]
CMD ["--version"]
