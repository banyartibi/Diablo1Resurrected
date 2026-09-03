#!/usr/bin/env bash
#
# DevilutionX HD & Resurrected Edition Launcher
# Features:
# - Multi-Pass Bloom & Dynamic Lighting Glow
# - 1440p Widescreen Resolution
# - Uncapped Framerate & Smooth Animation
# - Modern QoL (Run in town, Quick cast, Auto-gold, Health bars)
# - Custom 32-bit AI Upscaled Asset Pipeline
#

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$DIR/DevilutionX/build/devilutionx"
DATA_DIR="$HOME/.local/share/diasurgical/devilution"

if [ ! -f "$BIN" ]; then
    echo "Error: $BIN not found. Please build DevilutionX first."
    exit 1
fi

echo "========================================================"
echo "    Launching D1R-Biti - HD Resurrected                 "
echo "========================================================"
echo "Data directory:   $DATA_DIR"
echo "Binary:           $BIN"
echo "========================================================"

# Preload system SDL2 library (with full Wayland/X11 Vulkan & PipeWire support)
if [ -f "/usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0" ]; then
    export LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0:$LD_PRELOAD"
fi

exec "$BIN" --data-dir "$DATA_DIR" --config-dir "$DATA_DIR" --verbose "$@"
