#!/usr/bin/env bash
# AutoLoop Plugin Installer for Claude Code (Linux/macOS)
# Usage: curl -sL https://raw.githubusercontent.com/AdamHoldinPurge/autoloop-plugin/main/install.sh | bash
set -e

PLUGIN_DIR="$HOME/.claude/plugins/autoloop"
REPO_ZIP="https://github.com/AdamHoldinPurge/autoloop-plugin/archive/refs/heads/main.zip"
TMP_DIR=$(mktemp -d)

echo "=== AutoLoop Plugin Installer ==="
echo ""

# Check if already installed
if [ -d "$PLUGIN_DIR/.claude-plugin" ]; then
    echo "AutoLoop is already installed at $PLUGIN_DIR"
    read -rp "Reinstall/update? [y/N] " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        rm -rf "$TMP_DIR"
        exit 0
    fi
    echo "Updating existing installation..."
fi

# Download
echo "Downloading AutoLoop plugin..."
if command -v curl &>/dev/null; then
    curl -sL "$REPO_ZIP" -o "$TMP_DIR/autoloop.zip"
elif command -v wget &>/dev/null; then
    wget -q "$REPO_ZIP" -O "$TMP_DIR/autoloop.zip"
else
    echo "ERROR: curl or wget required"
    rm -rf "$TMP_DIR"
    exit 1
fi

# Extract
echo "Installing to $PLUGIN_DIR..."
unzip -qo "$TMP_DIR/autoloop.zip" -d "$TMP_DIR"

# Create plugin directory
mkdir -p "$PLUGIN_DIR"

# Copy files (preserve existing accounts.json if present)
EXTRACTED="$TMP_DIR/autoloop-plugin-main"
if [ -f "$PLUGIN_DIR/accounts/accounts.json" ]; then
    cp "$PLUGIN_DIR/accounts/accounts.json" "$TMP_DIR/accounts_backup.json"
fi

# Sync all plugin files
cp -r "$EXTRACTED/.claude-plugin" "$PLUGIN_DIR/"
cp -r "$EXTRACTED/scripts" "$PLUGIN_DIR/"
cp -r "$EXTRACTED/skills" "$PLUGIN_DIR/"
cp -f "$EXTRACTED"/icon* "$PLUGIN_DIR/" 2>/dev/null || true
cp -f "$EXTRACTED/.gitignore" "$PLUGIN_DIR/" 2>/dev/null || true

# Ensure accounts directory exists
mkdir -p "$PLUGIN_DIR/accounts"

# Restore accounts.json if it existed
if [ -f "$TMP_DIR/accounts_backup.json" ]; then
    cp "$TMP_DIR/accounts_backup.json" "$PLUGIN_DIR/accounts/accounts.json"
fi

# Fix marketplace.json to point to correct local path
cat > "$PLUGIN_DIR/.claude-plugin/marketplace.json" << EOF
{
  "name": "autoloop-local",
  "description": "Local marketplace for the autoloop plugin",
  "plugins": [
    {
      "name": "autoloop",
      "description": "Self-planning autonomous loop. Claude executes tasks, updates its own plan, and generates next steps — forever.",
      "version": "1.0.0",
      "source": {
        "type": "directory",
        "path": "$PLUGIN_DIR"
      }
    }
  ]
}
EOF

# Make scripts executable
chmod +x "$PLUGIN_DIR/scripts/"*.sh 2>/dev/null || true

# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "=== AutoLoop installed successfully! ==="
echo "Location: $PLUGIN_DIR"
echo ""
echo "Restart Claude Code to activate the plugin."
echo "Then use /start to begin an autonomous session."
