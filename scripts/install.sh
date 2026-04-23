#!/usr/bin/env bash
set -euo pipefail

# Install custom ccux fork to /Applications, replacing the existing app.
# Builds Release configuration, backs up current app, copies new build.

INSTALL_PATH="/Applications/ccux.app"
BACKUP_PATH="/Applications/ccux.app.backup"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== ccux fork installer ==="
echo "Project: $PROJECT_DIR"
echo "Install to: $INSTALL_PATH"
echo ""

# Step 1: Build Release
echo "[1/4] Building Release..."
cd "$PROJECT_DIR"
xcodebuild -project GhosttyTabs.xcodeproj \
  -scheme cmux \
  -configuration Release \
  -destination 'platform=macOS' \
  build 2>&1 | tail -5

# Find the built app
APP_PATH="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/Build/Products/Release/cmux.app" -print0 \
  | xargs -0 /usr/bin/stat -f "%m %N" 2>/dev/null \
  | sort -nr \
  | head -n 1 \
  | cut -d' ' -f2-
)"

if [[ -z "${APP_PATH}" ]]; then
  echo "ERROR: cmux.app not found in DerivedData after build" >&2
  exit 1
fi
echo "Built: $APP_PATH"

# Step 2: Quit running instance
echo "[2/4] Quitting running ccux..."
pkill -x cmux 2>/dev/null || true
pkill -x ccux 2>/dev/null || true
sleep 1

# Step 3: Backup and replace
echo "[3/4] Installing..."
if [[ -d "$INSTALL_PATH" ]]; then
  # Remove old backup if exists
  rm -rf "$BACKUP_PATH"
  # Backup current
  mv "$INSTALL_PATH" "$BACKUP_PATH"
  echo "Backed up to: $BACKUP_PATH"
fi

cp -R "$APP_PATH" "$INSTALL_PATH"
echo "Installed to: $INSTALL_PATH"

# Step 4: Launch
echo "[4/4] Launching..."
open "$INSTALL_PATH"

echo ""
echo "=== Done ==="
echo "To rollback: mv '$BACKUP_PATH' '$INSTALL_PATH'"
