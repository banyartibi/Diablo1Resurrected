#!/usr/bin/env python3
"""
Batch clean Real-ESRGAN edge fringe and regenerate clean 4X PBR maps across all themes:
- town
- cathedral
- catacombs
- caves
- hell
Uses pristine raw 4X files from assets/dungeon_pbr_{theme}_4x/raw/
"""

import os
import sys
from pathlib import Path
from PIL import Image
import numpy as np
import concurrent.futures

# Import functions from generate_hd_dungeon_pbr
sys.path.insert(0, str(Path(__file__).parent))
from generate_hd_dungeon_pbr import delight_image_4x, compute_pbr_maps_4x

def process_tile(task):
    raw_file, out_dir, ref_floor_arr = task
    stem = raw_file.stem
    try:
        img = Image.open(raw_file).convert("RGBA")
    except Exception as e:
        print(f"Error opening {raw_file}: {e}")
        return False

    w, h = img.size
    is_floor = (h <= 128)

    # 1. Delighting with fringe zeroed out
    delit_img = delight_image_4x(img, is_floor=is_floor, ref_floor_arr=ref_floor_arr)
    albedo_path = out_dir / "albedo" / f"{stem}.png"
    albedo_path.parent.mkdir(parents=True, exist_ok=True)
    delit_img.save(albedo_path, "PNG", optimize=True)

    # 2. Normal + Height, ORM, Roughness, Specular
    normal_img, orm_img, rough_img, spec_img = compute_pbr_maps_4x(delit_img, bump_strength=1.8)

    normal_path = out_dir / "normal" / f"{stem}_n.png"
    normal_path.parent.mkdir(parents=True, exist_ok=True)
    normal_img.save(normal_path, "PNG", optimize=True)

    orm_path = out_dir / "orm" / f"{stem}_orm.png"
    orm_path.parent.mkdir(parents=True, exist_ok=True)
    orm_img.save(orm_path, "PNG", optimize=True)

    rough_path = out_dir / "roughness" / f"{stem}_r.png"
    rough_path.parent.mkdir(parents=True, exist_ok=True)
    rough_img.save(rough_path, "PNG", optimize=True)

    spec_path = out_dir / "specular" / f"{stem}_s.png"
    spec_path.parent.mkdir(parents=True, exist_ok=True)
    spec_img.save(spec_path, "PNG", optimize=True)

    return True

def clean_theme(theme_name: str):
    base_dir = Path("/home/biti/antigravity/magical-bell")
    raw_dir = base_dir / f"assets/dungeon_pbr_{theme_name}_4x/raw"
    out_dir = base_dir / f"assets/dungeon_pbr_{theme_name}_4x"

    if not raw_dir.exists():
        print(f"[{theme_name}] Directory not found: {raw_dir}")
        return

    raw_files = sorted(list(raw_dir.glob("*.png")))
    if not raw_files:
        print(f"[{theme_name}] No files found in: {raw_dir}")
        return

    # Find reference floor tile for delighting (usually piece_0 or piece_2 or piece_100)
    ref_floor_arr = None
    for cand in ["piece_0.png", "piece_2.png", "piece_100.png"]:
        cand_path = raw_dir / cand
        if cand_path.exists():
            c_img = Image.open(cand_path).convert("RGBA")
            if c_img.size == (256, 128):
                c_arr = np.array(c_img, dtype=np.uint8).copy()
                c_arr[c_arr[:, :, 3] < 64] = 0
                lum = 0.299 * c_arr[:, :, 0] + 0.587 * c_arr[:, :, 1] + 0.114 * c_arr[:, :, 2]
                mask = c_arr[:, :, 3] > 128
                if np.sum((lum < 24.0) & mask) < 200:
                    ref_floor_arr = c_arr
                    break

    print(f"[{theme_name}] Cleaning {len(raw_files)} tiles...")
    tasks = [(f, out_dir, ref_floor_arr) for f in raw_files]

    workers = min(os.cpu_count() or 4, 16)
    with concurrent.futures.ProcessPoolExecutor(max_workers=workers) as executor:
        results = list(executor.map(process_tile, tasks))

    success = sum(1 for r in results if r)
    print(f"[{theme_name}] Completed {success}/{len(raw_files)} tiles successfully.")

def main():
    themes = ["town", "cathedral", "catacombs", "caves", "hell"]
    if len(sys.argv) > 1:
        themes = sys.argv[1:]

    for theme in themes:
        clean_theme(theme)

    print("\n[ALL DONE] All 4X PBR tiles successfully cleaned and regenerated without fringe.")

if __name__ == "__main__":
    main()
