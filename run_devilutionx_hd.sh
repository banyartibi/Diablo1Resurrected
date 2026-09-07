#!/bin/bash
#
# DevilutionX HD & Resurrected Edition Launcher  (LEGACY — DEPRECATED)
#
# DEPRECATED: A standalone DevilolutionX binary must NOT run on its own. Per the single-executable
# policy, ONLY ONE executable may ever run and it MUST be the Godot engine with the embedded
# GDExtension DevilutionX core (libdiablo.so). This holds even for legacy/original-2.5D rendering —
# that mode is served in-process by the Godot GDExtension, never by a separate DevilolutionX binary.
#
# This wrapper therefore refuses to launch standalone and redirects you to the in-process launcher:
#   ./run_d1_godot3d.sh
#
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================"
echo "    DevilolutionX HD Launcher  ->  DEPRECATED"
echo "========================================================"
echo "Refusing to start a standalone DevilolutionX process."
echo "Only one executable may run, and it must be the Godot engine + GDExtension."
echo "Redirecting to: ./run_d1_godot3d.sh"
echo "--------------------------------------------------------"

exec "$DIR/run_d1_godot3d.sh" "$@"
