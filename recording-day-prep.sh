#!/usr/bin/env bash
# recording-day-prep.sh
# Runs the night before recording days (Mon/Tue evenings — Sun/Mon at 10pm PT).
# Checks: scripts ready, equipment reminder, calendar clear, content summary.
# Posts briefing to #general by 8am (scheduled via cron for 10pm night before).
#
# Usage: bash recording-day-prep.sh [--dry-run]
#
# Cron: openclaw cron add --agent hermes --name "Recording Day Prep"
#         --schedule "0 22 * * 0,1" --tz "America/Los_Angeles"
#         --message "Run ~/.openclaw/scripts/recording-day-prep.sh"

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

GENERAL_CHANNEL="1476011153350987889"
SCRIPTS_DIR="$HOME/content-tools"
LOG_FILE="$HOME/.openclaw/logs/recording-day-prep.log"
DATE=$(date +%Y-%m-%d)
DAY_OF_WEEK=$(date +%u)   # 1=Mon … 7=Sun
TOMORROW=$(date -v+1d +%A 2>/dev/null || date -d tomorrow +%A 2>/dev/null)

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [recording-prep] $1" | tee -a "$LOG_FILE"
}

log "Starting recording day prep check (dry_run=$DRY_RUN, tomorrow=$TOMORROW)"

# ── 1. Detect recording day ────────────────────────────────────────────────────
# Recording days: Monday and Tuesday
# This script fires Sun night (before Mon) and Mon night (before Tue)
case "$TOMORROW" in
  Monday|Tuesday) RECORDING_DAY=true ;;
  *)              RECORDING_DAY=false ;;
esac

if [[ "$RECORDING_DAY" == "false" ]]; then
  log "Tomorrow ($TOMORROW) is not a recording day — exiting."
  exit 0
fi

log "Tomorrow is a recording day ($TOMORROW) — running prep checks."

# ── 2. Check: scripts directory exists ────────────────────────────────────────
SCRIPTS_STATUS="✅ content-tools repo found"
SCRIPTS_DETAIL=""

if [[ ! -d "$SCRIPTS_DIR" ]]; then
  SCRIPTS_STATUS="⚠️ content-tools repo not found at $SCRIPTS_DIR"
  SCRIPTS_DETAIL=" (run: git clone https://github.com/orcusauditory/content-tools ~/content-tools)"
else
  SCRIPT_COUNT=$(find "$SCRIPTS_DIR" -name "*.py" -o -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')
  SCRIPTS_STATUS="✅ content-tools ready ($SCRIPT_COUNT scripts)"
fi

# ── 3. Check: social-clip pipeline available ──────────────────────────────────
if [[ -f "$SCRIPTS_DIR/social-clip/social-clip.py" ]]; then
  CLIP_STATUS="✅ social-clip pipeline ready"
else
  CLIP_STATUS="⚠️ social-clip pipeline missing — run: git -C ~/content-tools pull"
fi

# ── 4. Check: ffmpeg available ────────────────────────────────────────────────
if command -v ffmpeg &>/dev/null; then
  FFMPEG_VER=$(ffmpeg -version 2>&1 | head -1 | awk '{print $3}')
  FFMPEG_STATUS="✅ ffmpeg $FFMPEG_VER"
else
  FFMPEG_STATUS="❌ ffmpeg not found — brew install ffmpeg"
fi

# ── 5. Check: calendar events tomorrow via gog ───────────────────────────────
CALENDAR_STATUS="📅 Calendar: check not available"
CALENDAR_CONFLICTS=""

if command -v openclaw &>/dev/null; then
  TOMORROW_DATE=$(date -v+1d +%Y-%m-%d 2>/dev/null || date -d tomorrow +%Y-%m-%d 2>/dev/null)
  CAL_RAW=$(openclaw gog calendar list --date "$TOMORROW_DATE" --json 2>/dev/null || echo "[]")
  EVENT_COUNT=$(echo "$CAL_RAW" | python3 -c "
import sys, json
try:
    events = json.load(sys.stdin)
    events = events if isinstance(events, list) else events.get('events', events.get('items', []))
    print(len(events))
except:
    print('?')
" 2>/dev/null || echo "?")

  if [[ "$EVENT_COUNT" == "0" ]]; then
    CALENDAR_STATUS="✅ Calendar clear tomorrow"
  elif [[ "$EVENT_COUNT" == "?" ]]; then
    CALENDAR_STATUS="📅 Calendar: could not fetch"
  else
    CALENDAR_STATUS="⚠️ $EVENT_COUNT event(s) tomorrow — check for conflicts"
    CALENDAR_CONFLICTS=$(echo "$CAL_RAW" | python3 -c "
import sys, json
try:
    events = json.load(sys.stdin)
    events = events if isinstance(events, list) else events.get('events', events.get('items', []))
    for e in events[:3]:
        title = e.get('summary', e.get('title', '?'))
        start = e.get('start', {})
        t = start.get('dateTime', start.get('date', ''))[:16].replace('T',' ')
        print(f'  • {t} — {title}')
except:
    pass
" 2>/dev/null || true)
  fi
fi

# ── 6. Equipment reminder ─────────────────────────────────────────────────────
EQUIPMENT_CHECKLIST=$(cat <<'CHECKLIST'
  🎙️ Mic plugged in + gain set
  🎧 Headphones charged
  💻 DAW open (GarageBand / Logic)
  📁 Session folder created for today
  🔇 Phone on Do Not Disturb
  🚪 Recording space quiet / door sign up
CHECKLIST
)

# ── 7. Content calendar status ────────────────────────────────────────────────
CONTENT_STATUS="📋 Content calendar: manual check needed"

# Check if there's a local content calendar file
for loc in \
  "$HOME/.openclaw-data/workspace/ref/CONTENT-CALENDAR.md" \
  "$HOME/content-tools/CONTENT-CALENDAR.md" \
  "$HOME/Dropbox/content-calendar.md"; do
  if [[ -f "$loc" ]]; then
    LINE_COUNT=$(wc -l < "$loc")
    CONTENT_STATUS="✅ Content calendar found ($loc, $LINE_COUNT lines)"
    break
  fi
done

# ── 8. Build message ──────────────────────────────────────────────────────────
MSG="🎙️ **Recording Day Prep — $TOMORROW**

**Readiness Check:**
$SCRIPTS_STATUS
$CLIP_STATUS
$FFMPEG_STATUS
$CALENDAR_STATUS$([ -n "$CALENDAR_CONFLICTS" ] && echo -e "\n$CALENDAR_CONFLICTS" || true)
$CONTENT_STATUS

**Equipment Checklist:**
$EQUIPMENT_CHECKLIST

**Quick commands:**
\`\`\`bash
# Generate social clip from today's recording:
python3 ~/content-tools/social-clip/social-clip.py recording.mp3 \\
  --caption \"Your Title\" --subtitle \"Out Now\"
\`\`\`

_Automated prep check — $(date -u +%Y-%m-%dT%H:%M)Z_"

log "Message prepared (${#MSG} chars)"

# ── 9. Send or dry-run ────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY RUN — message not sent:"
  echo "$MSG"
else
  log "Sending to #general ($GENERAL_CHANNEL)..."
  openclaw message send --channel "$GENERAL_CHANNEL" --message "$MSG"
  log "Sent successfully."
fi

log "Recording day prep complete."
