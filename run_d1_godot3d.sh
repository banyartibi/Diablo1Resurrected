#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="$DIR/tools/godot4/godot4"
GODOT_PROJ="$DIR/godot_d1_3d"
LIBEXT_SO="$DIR/godot_d1_3d/bin/libdiablo.linux.template_debug.x86_64.so"

echo "========================================================"
echo "    Launching Diablo 1: Resurrected – In-Process Engine "
echo "        Native Godot 4.7.2 GDExtension Architecture      "
echo "========================================================"

if [ ! -f "$GODOT" ]; then
    echo "ERROR: Godot 4 binary not found at $GODOT!"
    exit 1
fi

# SINGLE-EXECUTABLE GUARD (legacy IPC deprecation):
# Only ONE executable may ever run on the Godot engine, even in legacy/original-2.5D rendering.
# The standalone DevilutionX binary must NOT run side-by-side with the GDExtension build. Kill any
# stray standalone process before launch so we never end up with two DevilutionX processes.
for pid in $(pgrep -f "$DIR/DevilutionX/build/devilutionx" 2>/dev/null || true); do
    if [ "$pid" != "$$" ]; then
        echo "[single-exec] Killing stray standalone DevilutionX process (pid $pid) so only the Godot GDExtension runs..."
        kill "$pid" 2>/dev/null || true
    fi
done

if [ ! -f "$LIBEXT_SO" ]; then
    echo "ERROR: GDExtension library not found at $LIBEXT_SO!"
    echo "       Build it first with: ./build_gdextension.sh"
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
if [ -d "$DIR/assets" ]; then
    export D1_ASSETS_DIR="$DIR/assets"
else
    export D1_ASSETS_DIR="$DIR/DevilutionX/build/assets"
fi

# 3. Clean old SHM if any from legacy runs
rm -f /dev/shm/d1_godot_frame

echo "[1/1] Starting Godot 4.7.2 with embedded DevilutionX Core (GDExtension)..."
exec "$GODOT" --path "$GODOT_PROJ" "$@"
