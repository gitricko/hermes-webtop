#!/usr/bin/env bash
set -e

# Ensure we're running from the directory where the script lives
cd "$(dirname "$0")"

VENV_DIR="/tmp/hermes_automation_venv"

echo "🚀 Preparing Hermes Provider Automation..."

# Check if chromium or chromium-browser is installed natively on the system
if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
    echo "❌ System Chromium is not installed! Playwright requires it for automation."
    echo "Please install it manually. For example:"
    echo "  Ubuntu/Debian: sudo apt install chromium-browser"
    echo "  macOS: brew install chromium"
    exit 1
fi

# Check if the virtual environment exists, create it if missing
if [ ! -d "$VENV_DIR" ]; then
    echo "📦 Virtual environment not found. Creating a fresh one in '$VENV_DIR'..."
    python3 -m venv "$VENV_DIR"
    
    echo "📥 Upgrading pip..."
    "$VENV_DIR/bin/pip" install --upgrade pip
    
    if [ -f "requirements.txt" ]; then
        echo "📥 Installing dependencies from requirements.txt..."
        "$VENV_DIR/bin/pip" install -r requirements.txt
    else
        echo "⚠️  requirements.txt not found! Installing core dependencies manually..."
        "$VENV_DIR/bin/pip" install playwright playwright-stealth
    fi
else
    echo "✅ Virtual environment already exists at $VENV_DIR."
fi

echo "▶️  Launching headless automation script..."
# Run the script using the virtual environment's Python binary
"$VENV_DIR/bin/python" browser_reauth.py
