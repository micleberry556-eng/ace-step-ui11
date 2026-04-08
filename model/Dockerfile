# ACE-Step 1.5 AI Music Generation Model
# Requires: NVIDIA GPU + nvidia-container-toolkit on the host
#
# This image clones ACE-Step 1.5, installs all Python/CUDA dependencies,
# and runs the Gradio API server on port 8001.
# Models (~5GB) download automatically on first start and are cached in a volume.

FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# ── System packages ──────────────────────────────────────────────────────────
# Ubuntu 24.04 ships Python 3.12 which satisfies >=3.11,<3.13
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl wget git \
        python3 python3-venv python3-dev \
        build-essential \
        ffmpeg libsndfile1 \
        ca-certificates \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

# ── Install uv (Python package manager) ─────────────────────────────────────
ENV UV_INSTALL_DIR="/usr/local/bin"
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# ── Clone ACE-Step 1.5 ──────────────────────────────────────────────────────
WORKDIR /app
RUN git clone --depth 1 https://github.com/ace-step/ACE-Step-1.5.git /app

# ── Install Python dependencies via uv sync ──────────────────────────────────
# uv sync reads pyproject.toml, resolves PyTorch CUDA 12.8 wheels from the
# configured index, and installs everything including the local nano-vllm.
# This step takes 10-20 minutes and downloads ~8GB of packages.
RUN uv sync

# ── Directories for model cache and outputs ──────────────────────────────────
RUN mkdir -p /app/checkpoints /app/gradio_outputs

# ── Environment ──────────────────────────────────────────────────────────────
ENV TOKENIZERS_PARALLELISM=false
# Ensure the venv is used
ENV PATH="/app/.venv/bin:$PATH"
ENV VIRTUAL_ENV="/app/.venv"

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=3 \
    CMD curl -sf http://localhost:8001/health > /dev/null 2>&1 \
     || curl -sf http://localhost:8001/gradio_api/info > /dev/null 2>&1 \
     || exit 1

# ── Start API server ────────────────────────────────────────────────────────
# --enable-api exposes the Gradio endpoints the UI backend connects to
# --backend pt uses ~1.6GB VRAM (works on 4GB GPUs)
# --server-name 0.0.0.0 allows connections from other containers
CMD ["uv", "run", "acestep", "--port", "8001", "--enable-api", "--backend", "pt", "--server-name", "0.0.0.0"]
