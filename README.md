# content-tools

Orcus Auditory content production scripts and pipelines.

## Tools

### [`social-clip/`](./social-clip/)
Audio → vertical video pipeline for Instagram Reels, TikTok, YouTube Shorts.
1080×1920 MP4 with animated waveform, caption lower-third, Orcus Auditory branding.

```bash
python3 social-clip/social-clip.py episode.mp3 \
  --caption "Dark Fantasy" \
  --subtitle "New Episode Out Now" \
  --wave bars
```

## Requirements
- macOS with ffmpeg (`brew install ffmpeg`)
- Python 3 with Pillow (`pip3 install Pillow --break-system-packages`)
