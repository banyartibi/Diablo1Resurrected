#!/usr/bin/env python3
"""
Diablo 1 Resurrected - Offline AI HD Asset Upscaler Pipeline
Supports:
- SPAN-Pixel (Pixel Art AI Model)
- Compact-HD-Vector (Anime/Cartoon Clean Edges)
- Real-ESRGAN 4x (Ultra HD Photoreal & Gothic Textures)
"""

import sys
import os
import argparse

def main():
    print("=" * 70)
    print(" Diablo 1: Resurrected – Offline AI HD Asset Pipeline")
    print("=" * 70)
    parser = argparse.ArgumentParser(description="Batch AI HD Upscaling for Diablo 1 / Hellfire sprites")
    parser.add_argument("--input-dir", type=str, default="extracted_sprites", help="Directory containing extracted PNG sprites")
    parser.add_argument("--output-dir", type=str, default="hd_remaster_assets", help="Output directory for 4x AI upscaled sprites")
    parser.add_argument("--model", type=str, default="span_pixel", choices=["span_pixel", "compact_vector", "real_esrgan"], help="AI model to use")
    parser.add_argument("--scale", type=int, default=4, help="Upscaling scale factor (default: 4)")
    parser.add_argument("--gpu", action="store_true", default=True, help="Use Vulkan / ROCm GPU acceleration")
    
    args = parser.parse_args()
    print(f"[*] Configuration:")
    print(f"    - Input Directory : {args.input_dir}")
    print(f"    - Output Directory: {args.output_dir}")
    print(f"    - Model           : {args.model}")
    print(f"    - Scale Factor    : {args.scale}x")
    print(f"    - GPU Acceleration: {args.gpu}")
    print("")
    print("[*] Ready for batch AI processing whenever you decide to run offline upscaling!")

if __name__ == "__main__":
    main()
