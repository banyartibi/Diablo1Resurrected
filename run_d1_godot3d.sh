#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="$DIR/tools/godot4/godot4"
GODOT_PROJ="$DIR/godot_d1_3d"

echo "========================================================"
echo "    Launching Diablo 1: Resurrected – In-Process Engine "
echo "        Native Godot 4.7.2 GDExtension Architecture      "
echo "========================================================"

if [ ! -f "$GODOT" ]; then
    echo "ERROR: Godot 4 binary not found at $GODOT!"
    exit 1
fi

# 1. Setup isolated Godot environment
export XDG_DATA_HOME="$DIR/tools/godot4/data"
export XDG_CONFIG_HOME="$DIR/tools/godot4/config"
export XDG_CACHE_HOME="$DIR/tools/godot4/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

# 2. Setup runtime library paths for GDExtension (SDL2, BZip2, Vulkan)
export LD_LIBRARY_PATH="$DIR/DevilutionX/build/_deps/sdl2-build:$DIR/DevilutionX/build/3rdParty/bzip2:$DIR/godot_d1_3d/bin:$LD_LIBRARY_PATH"
export LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0:$LD_PRELOAD"

# 3. Clean old SHM if any from legacy runs
rm -f /dev/shm/d1_godot_frame

echo "[1/1] Starting Godot 4.7.2 with embedded DevilutionX Core (GDExtension)..."
exec "$GODOT" --path "$GODOT_PROJ" "$@"
