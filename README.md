# ⚔️ Diablo 1: Resurrected – Godot 4 3D Next-Gen Engine

**Diablo 1: Resurrected (D1R)** is a next-generation hybrid engine that marries the authentic, deterministic logic and gameplay of **DevilutionX** with the modern 3D Vulkan Forward+ rendering pipeline of **Godot Engine 4.7**.

---

## 🌟 Key Features

### 🎮 Dual-Engine Architecture
* **DevilutionX Core:** High-performance, bug-fixed Diablo 1 gameplay, AI, items, and inventory logic running offscreen with low-latency inter-process memory streaming via `/dev/shm/d1_godot_frame`.
* **Godot 4.7.2 Forward+ Vulkan Renderer:** Fully accelerated 3D scene compositing, dynamic lighting, post-processing, and volumetric atmosphere.

### 🔥 3D Next-Gen Visual Enhancements
* **AreaLight3D (Godot 4.7 New Feature):** Soft rectangular area light sources casting cinematic, diffuse amber illumination across dungeon cobblestones and through atmospheric smoke.
* **Procedural 3D Engine Flames & HDR Glow:** Real-time fluid noise fire simulations replacing classic 1996 8-frame torch sprites, radiating blinding HDR bloom into Godot's Forward+ post-processing stack.
* **3D Volumetric Fog:** Multi-layered, density-tuned atmospheric mist and Hellfire smoke drift reacting organically to scene lights.
* **GPUParticles3D:** 3D floating embers, sparks, and dungeon dust drifting dynamically between the camera and playfield.
* **3D Normal Relief & Embossing:** Tangent-space normal mapping giving physical depth, tactile edges, and specular reflections to stone floors, arches, and walls.
* **AMD FidelityFX CAS & 8K Catmull-Rom Splines:** Sub-pixel cubic Hermite vector smoothing and contrast-adaptive sharpening eliminating jagged pixel staircases.

### 🎛️ In-Game Hotkeys & Controls
* **Mouse Scroll Wheel:** Bidirectional in-game zoom:
  * **Scroll UP:** Zoom IN ($1.0\times \to 1.5\times \to 2.0\times \to 2.5\times \to 3.0\times$)
  * **Scroll DOWN:** Zoom OUT ($3.0\times \to 2.5\times \to 2.0\times \to 1.5\times \to 1.0\times$)
* **[F3]:** Toggle Godot 4.7 `AreaLight3D` (Soft Atmospheric Light Shafts)
* **[F4]:** Toggle V-Sync (Monitor Refresh Rate vs Uncapped Max FPS)
* **[F5]:** Toggle Procedural 3D Engine Torches & HDR Glow
* **[F7]:** Cycle Super-Resolution Upscalers (8K Catmull-Rom Spline / AMD FSR CAS / 3D Relief / Native)
* **[F8]:** Toggle Real-time FPS Counter
* **[F9]:** Cycle 3D Volumetric Fog Modes (Off / Crypt Mist / Dense Drift)
* **[F10]:** Cycle 3D Color Profiles (Vanilla 1996 / Dark Gothic OLED / Hellish Crimson / Crypt Cyan / Noir)
* **[F11]:** Cycle 3D Surface Relief Modes (Flat / Subtle / Deep 3D / Vector)

---

## 🚀 Quick Start

### Prerequisites
* Linux (Debian, Ubuntu, Arch, Fedora)
* Vulkan-compatible GPU (e.g. AMD Radeon RX 6000/7000, NVIDIA RTX, Intel Arc)
* Original `diabdat.mpq` (from your legal copy of Diablo 1 or GOG.com) placed in `~/.local/share/diasurgical/devilution/` or the project root.

### Launching the Game
```bash
./run_d1_godot3d.sh
```

---

## 🏗️ Building from Source

### 1. Build DevilutionX Core
```bash
cd DevilutionX
mkdir -p build && cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DDEVILUTIONX_SYSTEM_LIBS=OFF ..
ninja devilutionx
```

### 2. Run with Godot 4.7
The launcher script `./run_d1_godot3d.sh` automatically launches the background logic streamer and attaches the Godot 4 Forward+ 3D client.

---

## 📜 Credits & Licenses
* **DevilutionX Team:** Reverse engineered Diablo 1 engine ([Diasurgical](https://github.com/diasurgical/devilutionX)).
* **Godot Engine:** Open source 2D/3D engine ([Godot Engine](https://godotengine.org)).
* **Blizzard Entertainment:** Original Diablo 1 assets, audio, and game design.
