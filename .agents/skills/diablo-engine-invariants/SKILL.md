---
name: diablo-engine-invariants
description: >-
  Critical rules, mathematical invariants, and procedural safeguards for Diablo: Definitive Edition.
  Always consult and strictly adhere to this skill when modifying graphics, shaders, dungeon loading,
  PBR tile pipelines, lighting, gamma/brightness, or level transitions in the Diablo 1 codebase.
---

# Diablo: Definitive Edition Engine Invariants & Architecture Runbook

This skill enforces core architectural invariants and procedures to prevent recurring regressions in the Diablo: Definitive Edition engine (Godot 4.7.2 + DevilutionX GDExtension).

## Non-Negotiable Invariants

### 1. Town (Level 0) Must Never Load Pre-Baked PBR Assets
- Diablo 1 piece IDs are **per-theme** (Piece 2 in Cathedral is blood stone floor; Piece 2 in Town is grass).
- Town tiles must ALWAYS come directly from `diablo_bridge.get_dungeon_piece_texture(piece_id)`.
- Never create a folder called `dungeon_pbr_town_4x` with copied Cathedral assets.
- In `native_25d_view.gd`, both `get_pbr_or_base_texture()` and `get_pbr_or_base_special_texture()` must return `base_tex` immediately if `not is_cathedral_level()`.

### 2. Special CEL Archways Must Never Exist in Town
- `dSpecial` indices in Cathedral refer to stone arches, doorways, and columns.
- `dSpecial` indices in Town refer to tree leaf delay drawing (`towns.clx`), NOT archways.
- Special sprites in `native_25d_view.gd` line 825 must be gated by:
  `if special_id > 0 and is_cathedral_level() and (solidity_grid.size() < 112 * 112 or solidity_grid[idx] != 0):`
  NEVER check `last_level_idx == 0` for special archway sprites!

### 3. Butcher Room Walls (Pieces 180, 185..188) Height Requirement
- Cathedral wall pieces 180, 185, 186, 187, 188 are 4-row walls.
- In 1X: width 64, height 128.
- In 4X: width 256, height 512.
- The height must be 512px. Any shorter crop causes vertical shift, breaking door frames and wall alignment.

### 4. Gamma and Brightness Dual Sync
- Global post-processing brightness & gamma live in `view_brightness.gdshader` (driven by `bridge_receiver.gd`).
- The in-game palette in DevilutionX is updated via `diablo_bridge.set_gamma(g)`.
- Whenever gamma is changed in the options menu (`_on_opt_gamma_changed`), both `brightness_host.set_gamma_pct(g)` and `diablo_bridge.set_gamma(g)` must be called.
- Character sprites are unshaded in `entity_hd_upscaler.gdshader`. Therefore, `player_sprite.self_modulate` must provide healthy illumination:
  `Color(1.50, 1.46, 1.38)` in Town, `Color(1.48, 1.44, 1.36)` in Dungeons.

### 5. Transition to 100% Native Godot
- Every new feature and refactoring must move logic into native Godot (GDScript / C++ extension) rather than relying on legacy DevilutionX internals.
