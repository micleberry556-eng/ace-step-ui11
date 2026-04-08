#!/usr/bin/env bash
# =============================================================================
#  ACE-Step UI — Full Server Installation Script
#
#  Supported: Ubuntu 22.04+, Debian 12+, CentOS 9+, Fedora 39+, Arch Linux
#  Usage:     chmod +x install-server.sh && sudo ./install-server.sh
#
#  What this script does:
#    1. Installs system packages (Node.js 22, Python 3.11+, FFmpeg, Git, uv)
#    2. Optionally installs NVIDIA drivers + CUDA toolkit (for GPU inference)
#    3. Clones & sets up ACE-Step 1.5 (the AI music model)
#    4. Clones & sets up ACE-Step UI (frontend + backend)
#    5. Creates .env configuration
#    6. Installs systemd services for production auto-start
#    7. Starts all services
# =============================================================================

set -euo pipefail

# ── Configurable variables ───────────────────────────────────────────────────
INSTALL_DIR="${INSTALL_DIR:-/opt/ace-step}"
ACESTEP_REPO="https://github.com/ace-step/ACE-Step-1.5.git"
UI_REPO="${UI_REPO:-https://github.com/micleberry556-eng/ace-step-ui11.git}"
RUN_USER="${RUN_USER:-acestep}"
NODE_MAJOR=22
INSTALL_GPU="${INSTALL_GPU:-auto}"   # auto | yes | no
FRONTEND_PORT="${FRONTEND_PORT:-80}"
BACKEND_PORT="${BACKEND_PORT:-3001}"
API_PORT="${API_PORT:-8001}"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header(){ echo -e "\n${BOLD}══════════════════════════════════════════${NC}"; echo -e "${BOLD}  $*${NC}"; echo -e "${BOLD}══════════════════════════════════════════${NC}\n"; }

# ── Pre-flight checks ───────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  err "This script must be run as root (use sudo)."
  exit 1
fi

header "ACE-Step UI — Server Installation"

# ── Detect OS ────────────────────────────────────────────────────────────────
detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID}"
    OS_VERSION="${VERSION_ID:-}"
    OS_NAME="${PRETTY_NAME:-$ID}"
  else
    err "Cannot detect OS. /etc/os-release not found."
    exit 1
  fi
}

detect_os
info "Detected OS: ${OS_NAME}"

# ── Detect GPU ───────────────────────────────────────────────────────────────
detect_gpu() {
  if [[ "$INSTALL_GPU" == "yes" ]]; then
    return 0
  elif [[ "$INSTALL_GPU" == "no" ]]; then
    return 1
  fi
  # auto-detect
  if lspci 2>/dev/null | grep -qi nvidia; then
    return 0
  fi
  return 1
}

HAS_GPU=false
if detect_gpu; then
  HAS_GPU=true
  info "NVIDIA GPU detected — will install CUDA toolkit"
else
  warn "No NVIDIA GPU detected — AI model will run on CPU (much slower)"
fi

# ── Package manager helpers ──────────────────────────────────────────────────
install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq

  # Core tools
  apt-get install -y -qq curl wget git build-essential software-properties-common \
    ca-certificates gnupg lsb-release ffmpeg

  # Python 3.11+
  if ! python3 --version 2>/dev/null | grep -qE '3\.(1[1-9]|[2-9][0-9])'; then
    add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || true
    apt-get update -qq
    apt-get install -y -qq python3.11 python3.11-venv python3.11-dev
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 2>/dev/null || true
  fi

  # Node.js 22
  if ! node --version 2>/dev/null | grep -q "v${NODE_MAJOR}"; then
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
    apt-get install -y -qq nodejs
  fi

  # NVIDIA CUDA (if GPU)
  if [[ "$HAS_GPU" == true ]]; then
    if ! command -v nvidia-smi &>/dev/null; then
      info "Installing NVIDIA drivers..."
      apt-get install -y -qq nvidia-driver-550 2>/dev/null || \
        apt-get install -y -qq nvidia-driver 2>/dev/null || \
        warn "Could not auto-install NVIDIA drivers. Install manually."
    fi
    if ! command -v nvcc &>/dev/null; then
      info "Installing CUDA toolkit..."
      apt-get install -y -qq nvidia-cuda-toolkit 2>/dev/null || \
        warn "Could not auto-install CUDA toolkit. Install manually from https://developer.nvidia.com/cuda-downloads"
    fi
  fi
}

install_dnf() {
  dnf install -y curl wget git gcc gcc-c++ make ffmpeg python3.11 python3.11-devel \
    ca-certificates 2>/dev/null || \
  dnf install -y curl wget git gcc gcc-c++ make ffmpeg python3 python3-devel ca-certificates

  # Node.js 22
  if ! node --version 2>/dev/null | grep -q "v${NODE_MAJOR}"; then
    curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
    dnf install -y nodejs
  fi

  # NVIDIA (if GPU)
  if [[ "$HAS_GPU" == true ]]; then
    if ! command -v nvidia-smi &>/dev/null; then
      info "Installing NVIDIA drivers via RPM Fusion..."
      dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" 2>/dev/null || true
      dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" 2>/dev/null || true
      dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda 2>/dev/null || \
        warn "Could not auto-install NVIDIA drivers. Install manually."
    fi
  fi
}

install_pacman() {
  pacman -Syu --noconfirm
  pacman -S --noconfirm --needed curl wget git base-devel ffmpeg python nodejs npm

  if [[ "$HAS_GPU" == true ]]; then
    pacman -S --noconfirm --needed nvidia nvidia-utils cuda 2>/dev/null || \
      warn "Could not auto-install NVIDIA/CUDA. Install manually."
  fi
}

# ── Install system packages ──────────────────────────────────────────────────
header "Step 1/7 — Installing System Packages"

case "$OS_ID" in
  ubuntu|debian|linuxmint|pop)
    install_apt ;;
  fedora)
    install_dnf ;;
  centos|rhel|rocky|alma)
    # Enable EPEL + CRB for extra packages
    dnf install -y epel-release 2>/dev/null || true
    dnf config-manager --set-enabled crb 2>/dev/null || true
    install_dnf ;;
  arch|manjaro|endeavouros)
    install_pacman ;;
  *)
    err "Unsupported OS: $OS_ID. Please install manually: Node.js $NODE_MAJOR, Python 3.11+, FFmpeg, Git"
    exit 1 ;;
esac

ok "System packages installed"

# ── Verify core tools ───────────────────────────────────────────────────────
header "Step 2/7 — Verifying Dependencies"

check_cmd() {
  if command -v "$1" &>/dev/null; then
    ok "$1: $($1 --version 2>&1 | head -1)"
  else
    err "$1 not found!"
    return 1
  fi
}

check_cmd node
check_cmd npm
check_cmd python3
check_cmd git
check_cmd ffmpeg

if [[ "$HAS_GPU" == true ]]; then
  if command -v nvidia-smi &>/dev/null; then
    ok "nvidia-smi: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"
  else
    warn "nvidia-smi not found — GPU may not work until drivers are installed and system is rebooted"
  fi
fi

# ── Install uv (Python package manager) ─────────────────────────────────────
if ! command -v uv &>/dev/null; then
  info "Installing uv (Python package manager)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  # Also make it available for the service user
  if [[ -f "$HOME/.local/bin/uv" ]]; then
    cp "$HOME/.local/bin/uv" /usr/local/bin/uv 2>/dev/null || true
  fi
fi
ok "uv: $(uv --version 2>&1 | head -1)"

# ── Create service user ─────────────────────────────────────────────────────
header "Step 3/7 — Creating Service User"

if ! id "$RUN_USER" &>/dev/null; then
  useradd --system --create-home --home-dir "/home/$RUN_USER" --shell /bin/bash "$RUN_USER"
  ok "Created user: $RUN_USER"
else
  ok "User $RUN_USER already exists"
fi

# ── Create install directory ─────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
chown "$RUN_USER:$RUN_USER" "$INSTALL_DIR"

# ── Clone & set up ACE-Step 1.5 ─────────────────────────────────────────────
header "Step 4/7 — Installing ACE-Step 1.5 (AI Model)"

ACESTEP_DIR="$INSTALL_DIR/ACE-Step-1.5"

if [[ -d "$ACESTEP_DIR" ]]; then
  info "ACE-Step 1.5 already exists, pulling latest..."
  sudo -u "$RUN_USER" git -C "$ACESTEP_DIR" pull --ff-only 2>/dev/null || true
else
  info "Cloning ACE-Step 1.5 (this may take a moment)..."
  sudo -u "$RUN_USER" git clone --depth 1 "$ACESTEP_REPO" "$ACESTEP_DIR"
fi

info "Setting up Python environment for ACE-Step..."
sudo -u "$RUN_USER" bash -c "
  cd '$ACESTEP_DIR'
  export PATH=\"/usr/local/bin:\$HOME/.local/bin:\$PATH\"
  uv venv
  uv pip install -e .
"
ok "ACE-Step 1.5 installed at $ACESTEP_DIR"
info "Models (~5GB) will download automatically on first run"

# ── Clone & set up ACE-Step UI ───────────────────────────────────────────────
header "Step 5/7 — Installing ACE-Step UI"

UI_DIR="$INSTALL_DIR/ace-step-ui"

if [[ -d "$UI_DIR" ]]; then
  info "ACE-Step UI already exists, pulling latest..."
  sudo -u "$RUN_USER" git -C "$UI_DIR" pull --ff-only 2>/dev/null || true
else
  info "Cloning ACE-Step UI..."
  sudo -u "$RUN_USER" git clone --depth 1 "$UI_REPO" "$UI_DIR"
fi

info "Installing frontend dependencies..."
sudo -u "$RUN_USER" bash -c "cd '$UI_DIR' && npm ci --no-audit --no-fund"

info "Installing backend dependencies..."
sudo -u "$RUN_USER" bash -c "cd '$UI_DIR/server' && npm ci --no-audit --no-fund"

# Create data and audio directories
sudo -u "$RUN_USER" mkdir -p "$UI_DIR/server/data" "$UI_DIR/server/public/audio/reference-tracks"

ok "ACE-Step UI installed at $UI_DIR"

# ── Create .env configuration ────────────────────────────────────────────────
header "Step 6/7 — Configuring Environment"

ENV_FILE="$UI_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p | tr -d '\n' | head -c 64)
  cat > "$ENV_FILE" <<EOF
# ACE-Step UI Configuration (generated by install-server.sh)

# Path to ACE-Step installation
ACESTEP_PATH=$ACESTEP_DIR

# Server ports
PORT=$BACKEND_PORT
FRONTEND_PORT=$FRONTEND_PORT

# ACE-Step API
ACESTEP_API_URL=http://127.0.0.1:$API_PORT

# Database (SQLite)
DATABASE_PATH=$UI_DIR/server/data/acestep.db

# Storage
AUDIO_DIR=$UI_DIR/server/public/audio

# Frontend URL
FRONTEND_URL=http://localhost:$FRONTEND_PORT

# JWT Secret
JWT_SECRET=$JWT_SECRET

# Optional: Pexels API Key (for video backgrounds)
# Get a free key at https://www.pexels.com/api/
PEXELS_API_KEY=
EOF
  chown "$RUN_USER:$RUN_USER" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  ok "Configuration created at $ENV_FILE"
else
  ok "Configuration already exists at $ENV_FILE"
fi

# Also symlink for the server directory
if [[ ! -f "$UI_DIR/server/.env" ]]; then
  ln -sf "$ENV_FILE" "$UI_DIR/server/.env"
fi

# ── Install systemd services ────────────────────────────────────────────────
header "Step 7/7 — Installing Systemd Services"

# Resolve uv path for systemd
UV_PATH=$(command -v uv 2>/dev/null || echo "/usr/local/bin/uv")
NODE_PATH=$(command -v node 2>/dev/null || echo "/usr/bin/node")
NPM_PATH=$(command -v npm 2>/dev/null || echo "/usr/bin/npm")
NPX_PATH=$(command -v npx 2>/dev/null || echo "/usr/bin/npx")

# Service 1: ACE-Step API (Gradio — the AI model)
cat > /etc/systemd/system/acestep-api.service <<EOF
[Unit]
Description=ACE-Step 1.5 AI Music Generation API
After=network.target
Wants=network.target

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_USER
WorkingDirectory=$ACESTEP_DIR
Environment=PATH=/usr/local/bin:/usr/bin:/bin:/home/$RUN_USER/.local/bin
ExecStart=$UV_PATH run acestep --port $API_PORT --enable-api --backend pt --server-name 127.0.0.1
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal
SyslogIdentifier=acestep-api

# Resource limits
LimitNOFILE=65536
MemoryMax=90%

[Install]
WantedBy=multi-user.target
EOF

# Service 2: ACE-Step UI Backend (Express + SQLite)
cat > /etc/systemd/system/acestep-backend.service <<EOF
[Unit]
Description=ACE-Step UI Backend Server
After=network.target acestep-api.service
Wants=acestep-api.service

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_USER
WorkingDirectory=$UI_DIR/server
EnvironmentFile=$ENV_FILE
Environment=NODE_ENV=production
ExecStart=$NPX_PATH tsx src/index.ts
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=acestep-backend

[Install]
WantedBy=multi-user.target
EOF

# Service 3: ACE-Step UI Frontend (Vite dev server or nginx)
# Using Vite in preview mode for simplicity; for high-traffic use nginx + build
cat > /etc/systemd/system/acestep-frontend.service <<EOF
[Unit]
Description=ACE-Step UI Frontend
After=network.target acestep-backend.service
Wants=acestep-backend.service

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_USER
WorkingDirectory=$UI_DIR
EnvironmentFile=$ENV_FILE
ExecStartPre=$NPM_PATH run build
ExecStart=$NPX_PATH vite preview --host 0.0.0.0 --port $FRONTEND_PORT
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=acestep-frontend

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

# Enable services to start on boot
systemctl enable acestep-api.service
systemctl enable acestep-backend.service
systemctl enable acestep-frontend.service

ok "Systemd services installed and enabled"

# ── Start services ───────────────────────────────────────────────────────────
info "Starting services..."

systemctl start acestep-api.service
info "Waiting for AI model to initialize (this may take a few minutes on first run)..."
sleep 10

systemctl start acestep-backend.service
sleep 3

systemctl start acestep-frontend.service
sleep 3

# ── Print summary ────────────────────────────────────────────────────────────
header "Installation Complete!"

# Get server IP
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_SERVER_IP")

echo -e "  ${GREEN}All services are running!${NC}"
echo ""
echo -e "  ${BOLD}Access the app:${NC}"
echo -e "    Local:    http://localhost:${FRONTEND_PORT}"
echo -e "    Network:  http://${SERVER_IP}:${FRONTEND_PORT}"
echo ""
echo -e "  ${BOLD}Service management:${NC}"
echo -e "    Status:   sudo systemctl status acestep-api acestep-backend acestep-frontend"
echo -e "    Logs:     sudo journalctl -u acestep-api -f"
echo -e "              sudo journalctl -u acestep-backend -f"
echo -e "              sudo journalctl -u acestep-frontend -f"
echo -e "    Restart:  sudo systemctl restart acestep-api acestep-backend acestep-frontend"
echo -e "    Stop:     sudo systemctl stop acestep-api acestep-backend acestep-frontend"
echo ""
echo -e "  ${BOLD}Files:${NC}"
echo -e "    Install:  $INSTALL_DIR"
echo -e "    Config:   $ENV_FILE"
echo -e "    Database: $UI_DIR/server/data/acestep.db"
echo -e "    Audio:    $UI_DIR/server/public/audio/"
echo ""
echo -e "  ${BOLD}Ports:${NC}"
echo -e "    Frontend: $FRONTEND_PORT"
echo -e "    Backend:  $BACKEND_PORT"
echo -e "    AI API:   $API_PORT"
echo ""
if [[ "$HAS_GPU" == true ]]; then
  echo -e "  ${BOLD}GPU:${NC} NVIDIA GPU detected — inference will use CUDA"
else
  echo -e "  ${YELLOW}GPU:${NC} No GPU — inference will run on CPU (slower)"
  echo -e "       To use GPU, install NVIDIA drivers + CUDA and restart acestep-api"
fi
echo ""
echo -e "  ${BOLD}Firewall:${NC} Make sure ports $FRONTEND_PORT, $BACKEND_PORT are open"
echo -e "    Ubuntu:   sudo ufw allow $FRONTEND_PORT/tcp && sudo ufw allow $BACKEND_PORT/tcp"
echo -e "    CentOS:   sudo firewall-cmd --add-port=$FRONTEND_PORT/tcp --permanent && sudo firewall-cmd --reload"
echo ""
echo -e "  ${BOLD}First run:${NC} The AI model (~5GB) downloads automatically."
echo -e "  Check progress: sudo journalctl -u acestep-api -f"
echo ""
