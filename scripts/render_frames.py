#!/usr/bin/env python3
"""
render_frames.py
Read sim/vram_writes.txt produced by PS_Link_sim and render PNG frames + animated GIF.

Pixel format: 0x00RRGGBB  (bits 23:16 = R, 15:8 = G, 7:0 = B)
Display size:  320 x 240  (matches DISPLAY_WIDTH/HEIGHT with ENV_SIM)

Usage:
    python3 scripts/render_frames.py [vram_file] [--width W] [--height H] [--scale S] [--gif-delay MS]
Defaults: vram_file=sim/vram_writes.txt, W=320, H=240, S=2 (upscale for visibility), gif-delay=200ms
"""

import sys
import os
import argparse

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow is required.  Install with:  pip3 install Pillow")
    sys.exit(1)

DDR_BASE    = 0x0000_0000  # PS_Link_sim logs DDR-relative offsets
FRAMES_DIR  = "frames"

def make_image(framebuffer, width, height, scale):
    img = Image.new("RGB", (width, height))
    pixels = [
        ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
        for v in framebuffer
    ]
    img.putdata(pixels)
    if scale > 1:
        img = img.resize((width * scale, height * scale), Image.NEAREST)
    return img

def main():
    parser = argparse.ArgumentParser(description="Render VRAM write log to PNG frames + GIF")
    parser.add_argument("vram_file", nargs="?", default="sim/vram_writes.txt")
    parser.add_argument("--width",     type=int, default=320)
    parser.add_argument("--height",    type=int, default=240)
    parser.add_argument("--scale",     type=int, default=2, help="upscale factor for output images")
    parser.add_argument("--gif-delay", type=int, default=200, help="GIF frame delay in ms")
    args = parser.parse_args()

    width, height = args.width, args.height
    fb_size = width * height

    if not os.path.exists(args.vram_file):
        print(f"ERROR: {args.vram_file} not found.  Run scripts/run_sim.sh first.")
        sys.exit(1)

    os.makedirs(FRAMES_DIR, exist_ok=True)

    framebuffer = [0] * fb_size
    frame_num   = 0
    write_count = 0
    saved       = []
    gif_frames  = []

    with open(args.vram_file) as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue

            if line.startswith("FRAME_TICK") or line.startswith("FRAME_START"):
                img = make_image(framebuffer, width, height, args.scale)
                path = os.path.join(FRAMES_DIR, f"frame_{frame_num:04d}.png")
                img.save(path)
                gif_frames.append(img.copy())
                saved.append(path)
                print(f"  frame {frame_num:4d}  ({write_count} writes)  -> {path}")
                frame_num   += 1
                write_count  = 0
                continue

            parts = line.split()
            if len(parts) < 2:
                continue
            try:
                addr = int(parts[0], 16)
                data = int(parts[1], 16)
            except ValueError:
                continue

            pixel_idx = (addr - DDR_BASE) // 4
            if 0 <= pixel_idx < fb_size:
                framebuffer[pixel_idx] = data
                write_count += 1

    # Save whatever partial frame remains at end of simulation
    if write_count > 0 or frame_num == 0:
        img = make_image(framebuffer, width, height, args.scale)
        path = os.path.join(FRAMES_DIR, f"frame_{frame_num:04d}.png")
        img.save(path)
        gif_frames.append(img.copy())
        saved.append(path)
        print(f"  frame {frame_num:4d}  ({write_count} writes)  -> {path}  [partial]")

    print(f"\n{len(saved)} frame(s) saved to {FRAMES_DIR}/")

    # Generate animated GIF if we have multiple frames
    if len(gif_frames) >= 2:
        gif_path = os.path.join(FRAMES_DIR, "invaders.gif")
        gif_frames[0].save(
            gif_path,
            save_all=True,
            append_images=gif_frames[1:],
            duration=args.gif_delay,
            loop=0
        )
        print(f"Animated GIF: {gif_path}  ({len(gif_frames)} frames, {args.gif_delay}ms delay)")
    elif len(gif_frames) == 1:
        print("Only 1 frame captured — no animated GIF generated. Run longer simulation.")

if __name__ == "__main__":
    main()
