#!/bin/bash
echo "[start-tailscale] Starting tailscale..."

# Start the daemon with userspace networking
sudo tailscaled --statedir /config/.tailscale > /dev/null 2>&1 &

# Check if tailscaled is running (up to MAX_ATTEMPTS checks)
MAX_ATTEMPTS=30
for ((i=1; i<=MAX_ATTEMPTS; i++)); do
    if pidof tailscaled > /dev/null; then
        echo "[start-tailscale] tailscaled started successfully after $i seconds."
        break
    fi
    if [ "$i" -eq "$MAX_ATTEMPTS" ]; then
        echo "[start-tailscale] Failed to start tailscale daemon after $MAX_ATTEMPTS checks!"
        exit 1
    fi
    sleep 1
done

STATUS=$(tailscale status 2>&1)
if [[ "$STATUS" == *"Logged out."* ]]; then
    echo "[start-tailscale] Tailscale not logged in. Please run 'sudo tailscale up' manually."
else
    echo "[start-tailscale] Tailscale logged in."
fi