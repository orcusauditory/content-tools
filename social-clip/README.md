# social-clip.py — Audio to Vertical Social Video

Converts any audio file into a 1080×1920 (9:16) vertical video optimized for
Instagram Reels, TikTok, and YouTube Shorts.

## Usage

```bash
python3 ~/.openclaw/scripts/social-clip.py <audio_file> [options]
```

## Options

| Flag | Description | Default |
|---|---|---|
| `--caption` / `-c` | Main title text | Filename (title-cased) |
| `--subtitle` / `-s` | Tagline below caption | _(none)_ |
| `--output` / `-o` | Output MP4 path | `<stem>_social.mp4` |
| `--wave` / `-w` | Waveform style: `bars`, `line`, `mirror` | `bars` |

## Examples

```bash
# Basic — caption from filename
python3 social-clip.py episode-01-dark-fantasy.mp3

# Full options
python3 social-clip.py audio.mp3 \
  --caption "Dark Fantasy" \
  --subtitle "New Episode Out Now" \
  --wave bars \
  --output reels/dark-fantasy.mp4

# Line waveform for a smoother look
python3 social-clip.py meditation.mp3 --wave line

# Mirror waveform (symmetric peaks)
python3 social-clip.py teaser.mp3 --wave mirror --subtitle "Out Friday"
```

## Output Spec

- **Resolution:** 1080×1920 (Instagram/TikTok native)
- **Format:** MP4/H.264, AAC 192kbps, faststart (web-ready)
- **Branding:** Orcus Auditory top bar, orcusauditory.com watermark
- **Layout:** Brand bar → content area → animated waveform → caption lower-third

## Requirements

- `ffmpeg` (installed)
- `python3` with `Pillow` (`pip3 install Pillow --break-system-packages`)
- Fonts: Arial Bold, Arial Black (included with macOS)

## Notes

- Works with any audio format ffmpeg supports: mp3, wav, m4a, flac, ogg, aac
- No transcription/captions from audio content — caption is manually supplied
  (future: add `--whisper` flag when whisper is installed)
- For voice/narration audio, waveform will be significantly more dynamic than
  the test sine tone used for development
