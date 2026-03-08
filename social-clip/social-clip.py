#!/usr/bin/env python3
"""
social-clip.py — Audio to vertical social media video
Usage: python3 social-clip.py <audio_file> [options]

Generates a 9:16 vertical video with:
  - Animated waveform visualization
  - Caption overlay (from --caption or auto-derived from filename)
  - Orcus Auditory branding
  - Optimized for Instagram Reels, TikTok, YouTube Shorts
"""

import argparse
import os
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

# ── Defaults ────────────────────────────────────────────────────────────────

WIDTH   = 1080
HEIGHT  = 1920
FPS     = 30
BRAND   = "Orcus Auditory"
WEBSITE = "orcusauditory.com"

# Colors (hex without #)
BG_COLOR       = "0a0a0f"   # near-black
WAVE_COLOR_HEX = "#c084fc"  # violet/purple
WAVE_BG_HEX    = "#1a0a2e"  # dark purple
TEXT_COLOR      = "#f5f0ff"
ACCENT_COLOR    = "#c084fc"

# Font paths (macOS)
FONT_BOLD    = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BLACK   = "/System/Library/Fonts/Supplemental/Arial Black.ttf"

# Fallback fonts
FONT_FALLBACKS = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
]

def pick_font(preferred):
    if os.path.exists(preferred):
        return preferred
    for f in FONT_FALLBACKS:
        if os.path.exists(f):
            return f
    return None


def hex_to_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def get_audio_duration(audio_path: str) -> float:
    """Get audio duration in seconds using ffprobe."""
    result = subprocess.run([
        'ffprobe', '-v', 'quiet', '-print_format', 'json',
        '-show_format', audio_path
    ], capture_output=True, text=True)
    import json
    data = json.loads(result.stdout)
    return float(data['format']['duration'])


def build_branding_frame(tmpdir: str, caption: str, subtitle: str) -> str:
    """Generate a PNG frame with caption text and branding using Pillow."""
    from PIL import Image, ImageDraw, ImageFont

    img = Image.new('RGBA', (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # ── Top brand bar ────────────────────────────────────────────────────────
    bar_h = 100
    draw.rectangle([0, 0, WIDTH, bar_h], fill=(*hex_to_rgb(ACCENT_COLOR), 220))

    font_brand = None
    font_path = pick_font(FONT_BOLD)
    if font_path:
        try:
            font_brand = ImageFont.truetype(font_path, 38)
        except Exception:
            pass
    if font_brand is None:
        font_brand = ImageFont.load_default()

    brand_text = BRAND
    bbox = draw.textbbox((0, 0), brand_text, font=font_brand)
    bw = bbox[2] - bbox[0]
    draw.text(((WIDTH - bw) // 2, (bar_h - (bbox[3] - bbox[1])) // 2), brand_text,
              fill=(10, 10, 15, 255), font=font_brand)

    # ── Caption block (lower third) ──────────────────────────────────────────
    caption_area_y = HEIGHT - 520
    caption_area_h = 360

    # Semi-transparent background
    overlay = Image.new('RGBA', (WIDTH, caption_area_h), (0, 0, 0, 0))
    ov_draw = ImageDraw.Draw(overlay)
    ov_draw.rectangle([0, 0, WIDTH, caption_area_h], fill=(10, 5, 30, 210))
    img.alpha_composite(overlay, dest=(0, caption_area_y))

    # Accent line
    draw.rectangle([0, caption_area_y, WIDTH, caption_area_y + 4],
                   fill=(*hex_to_rgb(ACCENT_COLOR), 255))

    # Caption text
    font_caption = None
    font_caption_path = pick_font(FONT_BLACK)
    if font_caption_path:
        try:
            font_caption = ImageFont.truetype(font_caption_path, 58)
        except Exception:
            pass
    if font_caption is None:
        font_caption = ImageFont.load_default()

    # Wrap caption
    wrapped = textwrap.wrap(caption, width=22)[:4]
    y_text = caption_area_y + 24
    for line in wrapped:
        bbox = draw.textbbox((0, 0), line, font=font_caption)
        lw = bbox[2] - bbox[0]
        draw.text(((WIDTH - lw) // 2, y_text), line,
                  fill=(*hex_to_rgb(TEXT_COLOR), 255), font=font_caption)
        y_text += (bbox[3] - bbox[1]) + 10

    # Subtitle
    if subtitle:
        font_sub = None
        font_sub_path = pick_font(FONT_REGULAR)
        if font_sub_path:
            try:
                font_sub = ImageFont.truetype(font_sub_path, 34)
            except Exception:
                pass
        if font_sub is None:
            font_sub = ImageFont.load_default()

        bbox = draw.textbbox((0, 0), subtitle, font=font_sub)
        sw = bbox[2] - bbox[0]
        draw.text(((WIDTH - sw) // 2, y_text + 10), subtitle,
                  fill=(*hex_to_rgb(ACCENT_COLOR), 255), font=font_sub)

    # ── Website watermark ────────────────────────────────────────────────────
    font_wm = None
    if font_path:
        try:
            font_wm = ImageFont.truetype(font_path, 28)
        except Exception:
            pass
    if font_wm is None:
        font_wm = ImageFont.load_default()

    wm_text = f"✦ {WEBSITE}"
    bbox = draw.textbbox((0, 0), wm_text, font=font_wm)
    ww = bbox[2] - bbox[0]
    draw.text(((WIDTH - ww) // 2, HEIGHT - 90), wm_text,
              fill=(180, 150, 255, 180), font=font_wm)

    out = os.path.join(tmpdir, 'branding.png')
    img.save(out, 'PNG')
    return out


def run_ffmpeg(args: list, desc: str):
    print(f"  [ffmpeg] {desc}...")
    result = subprocess.run(
        ['ffmpeg', '-y', '-loglevel', 'error'] + args,
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"  ERROR: {result.stderr[:500]}", file=sys.stderr)
        sys.exit(1)


def build_video(audio_path: str, output_path: str, caption: str,
                subtitle: str, waveform_style: str):
    duration = get_audio_duration(audio_path)
    print(f"  Audio: {Path(audio_path).name} ({duration:.1f}s)")
    print(f"  Caption: {caption!r}")
    print(f"  Output: {output_path}")

    with tempfile.TemporaryDirectory() as tmpdir:
        # 1. Generate branding overlay frame
        print("  Generating branding frame...")
        branding_png = build_branding_frame(tmpdir, caption, subtitle)

        # 2. Waveform style params
        wave_styles = {
            'bars':   f"showwaves=s={WIDTH}x400:mode=cline:colors={WAVE_COLOR_HEX}|{WAVE_COLOR_HEX}:rate={FPS}:scale=lin",
            'line':   f"showwaves=s={WIDTH}x400:mode=line:colors={WAVE_COLOR_HEX}|{WAVE_COLOR_HEX}:rate={FPS}:scale=sqrt",
            'mirror': f"showwaves=s={WIDTH}x400:mode=p2p:colors={WAVE_COLOR_HEX}|{WAVE_COLOR_HEX}:rate={FPS}:scale=lin",
        }
        wave_filter = wave_styles.get(waveform_style, wave_styles['bars'])

        # Waveform Y position (center of video, above lower third)
        wave_y = (HEIGHT // 2) - 200  # center the 400px wave vertically

        # 3. Build final video via complex filtergraph
        # Layout: black bg → wave strip (lighten blend of wavebg+waveform) → branding
        vf = (
            # Black background canvas
            f"color=c=#{BG_COLOR}:s={WIDTH}x{HEIGHT}:r={FPS}[bg];"
            # Dark purple wave background strip (400px tall, same size as waveform)
            f"color=c=#{WAVE_BG_HEX.lstrip('#')}:s={WIDTH}x400:r={FPS}[wavebg];"
            # Generate waveform from audio (colored on black bg)
            f"[0:a]{wave_filter}[wave];"
            # Lighten blend: max(wavebg, wave) per channel
            # → black waveform areas show dark purple bg; colored wave areas show the wave
            f"[wavebg][wave]blend=all_mode=lighten[wavestrip];"
            # Composite wave strip onto main canvas at vertical center
            f"[bg][wavestrip]overlay=x=0:y={wave_y}[canvas];"
            # Overlay branding/caption PNG (looped for full duration)
            f"[canvas][1:v]overlay=x=0:y=0[out]"
        )

        tmp_output = os.path.join(tmpdir, 'output.mp4')

        run_ffmpeg([
            '-i', audio_path,
            '-loop', '1', '-i', branding_png,
            '-filter_complex', vf,
            '-map', '[out]',
            '-map', '0:a',
            '-c:v', 'libx264',
            '-preset', 'fast',
            '-crf', '22',
            '-c:a', 'aac',
            '-b:a', '192k',
            '-t', str(duration),
            '-pix_fmt', 'yuv420p',
            '-movflags', '+faststart',
            tmp_output,
        ], f"Rendering {WIDTH}x{HEIGHT} @ {FPS}fps")

        import shutil
        shutil.move(tmp_output, output_path)

    print(f"\n✅ Done: {output_path}")
    size_mb = os.path.getsize(output_path) / 1024 / 1024
    print(f"   Size: {size_mb:.1f} MB | Duration: {duration:.1f}s")


def main():
    parser = argparse.ArgumentParser(
        description='Convert audio to vertical social media video',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic usage (caption from filename)
  python3 social-clip.py episode-01.mp3

  # Custom caption and subtitle
  python3 social-clip.py audio.mp3 --caption "Dark Fantasy" --subtitle "New Episode Out Now"

  # Different waveform style, custom output
  python3 social-clip.py audio.mp3 --wave line --output reels/clip.mp4

Waveform styles:  bars (default), line, mirror
Output formats:   MP4/H.264 — compatible with all platforms
        """)

    parser.add_argument('audio', help='Input audio file (mp3, wav, m4a, flac, etc.)')
    parser.add_argument('--caption', '-c', help='Main caption text (default: filename stem)')
    parser.add_argument('--subtitle', '-s', default='', help='Subtitle/tagline below caption')
    parser.add_argument('--output', '-o', help='Output video path (default: <audio_stem>_social.mp4)')
    parser.add_argument('--wave', '-w', default='bars',
                        choices=['bars', 'line', 'mirror'],
                        help='Waveform visualization style (default: bars)')

    args = parser.parse_args()

    audio_path = args.audio
    if not os.path.exists(audio_path):
        print(f"Error: audio file not found: {audio_path}", file=sys.stderr)
        sys.exit(1)

    stem = Path(audio_path).stem
    caption = args.caption or stem.replace('-', ' ').replace('_', ' ').title()

    output_path = args.output or str(Path(audio_path).with_name(f"{stem}_social.mp4"))

    print(f"\n🎬 Social Clip Pipeline — {BRAND}")
    print(f"   {WIDTH}x{HEIGHT} • {FPS}fps • {args.wave} waveform\n")

    build_video(
        audio_path=audio_path,
        output_path=output_path,
        caption=caption,
        subtitle=args.subtitle,
        waveform_style=args.wave,
    )


if __name__ == '__main__':
    main()
