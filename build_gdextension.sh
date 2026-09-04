#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== 1/2 Recompiling DevilutionX Core ==="
ninja -C "$DIR/DevilutionX/build"

echo "=== 2/2 Building Godot 4.7 GDExtension (DiabloBridge) ==="
mkdir -p "$DIR/godot_d1_extension/build"
cmake -B "$DIR/godot_d1_extension/build" -S "$DIR/godot_d1_extension" -G Ninja
ninja -C "$DIR/godot_d1_extension/build"

echo "=== Build Successful: godot_d1_3d/bin/libdiablo.linux.template_debug.x86_64.so ==="
