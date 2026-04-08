#!/usr/bin/env bash
# =============================================================================
#  ACE-Step UI — Server Uninstall Script
#  Usage: sudo ./uninstall-server.sh
# =============================================================================

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/ace-step}"
RUN_USER="${RUN_USER:-acestep}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)." >&2
  exit 1
fi

echo -e "${BOLD}ACE-Step UI — Uninstall${NC}"
echo ""
echo "This will:"
echo "  - Stop and remove systemd services"
echo "  - Remove $INSTALL_DIR (including database and audio files)"
echo "  - Remove the $RUN_USER system user"
echo ""
read -rp "Are you sure? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Cancelled."
  exit 0
fi

echo ""

# Stop and disable services
for svc in acestep-frontend acestep-backend acestep-api; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo "Stopping $svc..."
    systemctl stop "$svc"
  fi
  if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
    systemctl disable "$svc"
  fi
  rm -f "/etc/systemd/system/${svc}.service"
done
systemctl daemon-reload
echo -e "${GREEN}[OK]${NC} Services removed"

# Remove install directory
if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
  echo -e "${GREEN}[OK]${NC} Removed $INSTALL_DIR"
fi

# Remove user
if id "$RUN_USER" &>/dev/null; then
  userdel -r "$RUN_USER" 2>/dev/null || userdel "$RUN_USER"
  echo -e "${GREEN}[OK]${NC} Removed user $RUN_USER"
fi

echo ""
echo -e "${GREEN}Uninstall complete.${NC}"
echo "Note: System packages (Node.js, Python, FFmpeg, NVIDIA drivers) were NOT removed."
