#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
REPO_URL="https://raw.githubusercontent.com/phanendra-t/ArchagentCLI/main/archagent"

echo "ArchAgent CLI Installer"
echo

# Check dependencies
echo "Checking dependencies..."
missing=0
for dep in bash curl jq; do
    if command -v "$dep" &>/dev/null; then
        version=$("$dep" --version 2>&1 | head -1)
        echo "  ✓ $dep ($version)"
    else
        echo "  ✗ $dep — MISSING"
        missing=1
    fi
done

if [ "$missing" = 1 ]; then
    echo
    echo "Install missing dependencies first:"
    echo "  macOS:  brew install jq"
    echo "  Ubuntu: sudo apt install jq"
    echo "  RHEL:   sudo yum install jq"
    exit 1
fi

# Download and install
echo
echo "Downloading archagent..."
mkdir -p "$INSTALL_DIR"
curl -fsSL "$REPO_URL" -o "$INSTALL_DIR/archagent"
chmod +x "$INSTALL_DIR/archagent"

echo "✓ Installed to $INSTALL_DIR/archagent"

# PATH check
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo
    echo "⚠ $INSTALL_DIR is not in your PATH. Add this to your ~/.bashrc or ~/.zshrc:"
    echo
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo
echo "Verify with: archagent --version"
