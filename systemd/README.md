# Systemd Service Files

These service files run ACE-Step UI as a production service on Linux servers.

## Quick Install

```bash
# Copy all service files
sudo cp acestep-*.service /etc/systemd/system/

# Edit paths in each file to match your installation
sudo nano /etc/systemd/system/acestep-api.service
sudo nano /etc/systemd/system/acestep-backend.service
sudo nano /etc/systemd/system/acestep-frontend.service

# Reload, enable, and start
sudo systemctl daemon-reload
sudo systemctl enable --now acestep-api acestep-backend acestep-frontend
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| `acestep-api` | 8001 | ACE-Step 1.5 Gradio API (AI model) |
| `acestep-backend` | 3001 | Express server (API, database, audio) |
| `acestep-frontend` | 80 | Vite production build (web UI) |

## Management

```bash
# Check status
sudo systemctl status acestep-api acestep-backend acestep-frontend

# View logs (live)
sudo journalctl -u acestep-api -f
sudo journalctl -u acestep-backend -f
sudo journalctl -u acestep-frontend -f

# Restart all
sudo systemctl restart acestep-api acestep-backend acestep-frontend

# Stop all
sudo systemctl stop acestep-frontend acestep-backend acestep-api
```

## Notes

- The `acestep-api` service downloads ~5GB of AI models on first start.
- Services start in order: api -> backend -> frontend.
- If using the automated `install-server.sh`, these files are created automatically.
