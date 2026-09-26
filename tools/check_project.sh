#!/usr/bin/env bash
# Runs every automated check headless (no window, no GPU needed).
#
# Usage:  GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 tools/check_project.sh
#
#   1. import the project (builds the .godot/ cache, like opening it in the editor)
#   2. load every script / scene / resource / shader       (tools/validate.tscn)
#   3. editor diagnostics: GDScript errors AND warnings      (tools/lsp_diagnostics.py)
#   4. gameplay smoke test: autopilot, restart, defeat, victory, swim, pause, menu
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

echo "== 1/4 Import project"
"$GODOT" --headless --path . --editor --quit > /dev/null 2>&1

echo "== 2/4 Load all project files"
"$GODOT" --headless --path . res://tools/validate.tscn 2>&1 | grep -E "validate|ERROR"

echo "== 3/4 Editor diagnostics (errors + warnings)"
python3 tools/lsp_diagnostics.py "$GODOT" .

echo "== 4/4 Gameplay smoke test (about 1 minute)"
"$GODOT" --headless --path . -- --autotest=40 --bots=8 2>&1 | grep -E "^\[auto\] (swim|paused|back|shots|avg|result|AUTOTEST)|SCRIPT ERROR|WATCHDOG"
echo "All checks passed."
