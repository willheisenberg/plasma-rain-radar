#!/usr/bin/env bash
set -e

# Path to this script's directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
PROJECT_DIR="$(dirname "$DIR")"

cd "$PROJECT_DIR"

echo "=== 1. Compiling shader ==="
if /usr/lib/qt6/bin/qsb --qt6 -o contents/ui/radar_cleaner.frag.qsb contents/ui/radar_cleaner.frag; then
    echo "✓ Shader compiled successfully."
else
    echo "✗ Failed to compile shader!"
    exit 1
fi

echo "=== 2. Updating Plasma Widget ==="
if kpackagetool6 -t Plasma/Applet -u .; then
    echo "✓ Widget package updated."
else
    echo "✗ Failed to update widget package!"
    exit 1
fi

echo "=== 3. Restarting Plasmashell ==="
if systemctl --user restart plasma-plasmashell.service; then
    echo "✓ Plasmashell restarted successfully."
else
    echo "✗ Failed to restart plasmashell!"
    exit 1
fi

echo "=== Success! The new settings are active. ==="
