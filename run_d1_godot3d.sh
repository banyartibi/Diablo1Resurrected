#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$DIR/DevilutionX/build/devilutionx"
GODOT="$DIR/tools/godot4/godot4"
GODOT_PROJ="$DIR/godot_d1_3d"

echo "========================================================"
echo "    Launching D1R-Biti -> Godot 4.7.2 3D Next-Gen       "
echo "========================================================"

if [ ! -f "$BIN" ]; then
    echo "ERROR: DevilutionX binary not found at $BIN!"
    exit 1
fi

if [ ! -f "$GODOT" ]; then
    echo "ERROR: Godot 4 binary not found at $GODOT!"
    exit 1
fi

# 1. Clean old shared memory buffer if any
rm -f /dev/shm/d1_godot_frame

# 2. Setup isolated Godot environment
export XDG_DATA_HOME="$DIR/tools/godot4/data"
export XDG_CONFIG_HOME="$DIR/tools/godot4/config"
export XDG_CACHE_HOME="$DIR/tools/godot4/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

# 3. Setup DevilutionX runtime preload for Debian Wayland/X11
export LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0:$LD_PRELOAD"

cleanup() {
    echo "Shutting down D1R-Biti & Godot 4..."
    kill -TERM "$D1_PID" 2>/dev/null || true
    kill -TERM "$GODOT_PID" 2>/dev/null || true
    rm -f /dev/shm/d1_godot_frame
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

DATA_DIR="$HOME/.local/share/diasurgical/devilution"
export D1_MINIMIZE_WINDOW=1

echo "[1/2] Launching DevilutionX logic & frame streamer (offscreen in background)..."
"$BIN" --data-dir "$DATA_DIR" --config-dir "$DATA_DIR" --hellfire --vulkan "$@" &
D1_PID=$!

echo "[2/2] Waiting for DevilutionX stream initialization..."
for i in {1..40}; do
    if [ -f /dev/shm/d1_godot_frame ]; then
        break
    fi
    sleep 0.1
done

echo "[3/3] Launching Godot 4.7.2 3D Renderer (Fullscreen)..."
"$GODOT" --path "$GODOT_PROJ" &
GODOT_PID=$!

echo "Godot 4.7.2 3D Renderer active in fullscreen!"
wait -n "$D1_PID" "$GODOT_PID"
cleanup
