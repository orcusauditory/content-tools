#!/usr/bin/env bash
# recording-day-prep.sh
# Runs at 7:30am on recording days (Mon + Tue) and posts a readiness briefing
# to #general before the 8am window.
#
# Cron: 30 7 * * 1,2 America/Los_Angeles (job id: 4816f879)
#
# Usage: bash recording-day-prep.sh [--dry-run]

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

GENERAL_CHANNEL="1476011153350987889"
SCRIPTS_DIR="$HOME/content-tools"
LOG_FILE="$HOME/.openclaw/logs/recording-day-prep.log"
MC_API="http://localhost:3000/api"

TODAY=$(date +%A)              # Monday / Tuesday / etc.
TODAY_DATE=$(date +%Y-%m-%d)
WEEK_END=$(date -v+7d +%Y-%m-%d 2>/dev/null || date -d "+7 days" +%Y-%m-%d)

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [recording-prep] $1" | tee -a "$LOG_FILE"
}

log "Starting recording day prep (dry_run=$DRY_RUN, today=$TODAY/$TODAY_DATE)"

# ── 1. Verify this is actually a recording day ─────────────────────────────────
case "$TODAY" in
  Monday|Tuesday) : ;;
  *)
    log "Today ($TODAY) is not a recording day — exiting."
    exit 0
    ;;
esac

# ── 2. Tool checks ────────────────────────────────────────────────────────────
SCRIPTS_STATUS="✅ content-tools ready"
if [[ ! -d "$SCRIPTS_DIR" ]]; then
  SCRIPTS_STATUS="⚠️ ~/content-tools not found (git clone https://github.com/orcusauditory/content-tools)"
elif [[ ! -f "$SCRIPTS_DIR/social-clip/social-clip.py" ]]; then
  SCRIPTS_STATUS="⚠️ social-clip missing — run: git -C ~/content-tools pull"
fi

FFMPEG_STATUS="✅ ffmpeg ready"
if ! command -v ffmpeg &>/dev/null; then
  FFMPEG_STATUS="❌ ffmpeg not found — brew install ffmpeg"
fi

# ── 3. Calendar: conflicts today ──────────────────────────────────────────────
CALENDAR_STATUS="📅 Calendar unavailable"
CONFLICT_DETAIL=""

CAL_JSON=$(curl -sf "$MC_API/calendar" 2>/dev/null || echo "[]")
if [[ "$CAL_JSON" != "[]" && -n "$CAL_JSON" ]]; then
  CONFLICT_RESULT=$(echo "$CAL_JSON" | python3 -c "
import sys, json
from datetime import date, datetime

today_str = '$(date +%Y-%m-%d)'
events = json.load(sys.stdin)
if not isinstance(events, list):
    events = events.get('events', events.get('items', []))

conflicts = []
for e in events:
    start = e.get('start', '')
    if isinstance(start, dict):
        start = start.get('dateTime', start.get('date', ''))
    if start.startswith(today_str):
        summary = e.get('summary', '?')
        t = start[11:16] if 'T' in start else 'all day'
        conflicts.append(f'{t} — {summary}')

print(len(conflicts))
for c in conflicts:
    print(c)
" 2>/dev/null || echo "0")

  CONFLICT_COUNT=$(echo "$CONFLICT_RESULT" | head -1)
  if [[ "$CONFLICT_COUNT" == "0" ]]; then
    CALENDAR_STATUS="✅ Calendar clear today"
  else
    CALENDAR_STATUS="⚠️ $CONFLICT_COUNT event(s) today — check for recording conflicts"
    CONFLICT_DETAIL=$(echo "$CONFLICT_RESULT" | tail -n +2 | sed 's/^/  • /')
  fi
fi

# ── 4. Content calendar: check for recording/content items this week ──────────
CONTENT_STATUS="📋 Content calendar: no upcoming items found"
CONTENT_DETAIL=""

if [[ "$CAL_JSON" != "[]" && -n "$CAL_JSON" ]]; then
  CONTENT_RESULT=$(echo "$CAL_JSON" | python3 -c "
import sys, json, re
from datetime import date

today_str = '$(date +%Y-%m-%d)'
week_end_str = '$WEEK_END'
today = date.fromisoformat(today_str)
week_end = date.fromisoformat(week_end_str)

KEYWORDS = r'record|episode|content|audio|publish|release|edit|podcast|narrat|script|studio'

events = json.load(sys.stdin)
if not isinstance(events, list):
    events = events.get('events', events.get('items', []))

content_items = []
for e in events:
    summary = e.get('summary', '')
    desc = e.get('description', '')
    text = (summary + ' ' + desc).lower()
    if re.search(KEYWORDS, text, re.I):
        start = e.get('start', '')
        if isinstance(start, dict):
            start = start.get('dateTime', start.get('date', ''))
        date_part = start[:10]
        try:
            ev_date = date.fromisoformat(date_part)
            if today <= ev_date <= week_end:
                t = start[11:16] if 'T' in start else ''
                label = f'{date_part} {t}'.strip()
                content_items.append(f'{label} — {summary}')
        except:
            pass

print(len(content_items))
for c in content_items:
    print(c)
" 2>/dev/null || echo "0")

  CONTENT_COUNT=$(echo "$CONTENT_RESULT" | head -1)
  if [[ "$CONTENT_COUNT" == "0" ]]; then
    CONTENT_STATUS="⚠️ No recording/content events found in calendar this week — consider adding to Google Calendar"
  else
    CONTENT_STATUS="✅ $CONTENT_COUNT content item(s) on calendar this week"
    CONTENT_DETAIL=$(echo "$CONTENT_RESULT" | tail -n +2 | sed 's/^/  • /')
  fi
fi

# ── 5. Equipment checklist ────────────────────────────────────────────────────
EQUIPMENT=$(cat <<'EQ'
  🎙️ Mic plugged in + gain set
  🎧 Headphones charged
  💻 DAW open (GarageBand / Logic)
  📁 Session folder created for today
  🔇 Phone on Do Not Disturb
  🚪 Recording space quiet / door sign up
EQ
)

# ── 6. Build message ──────────────────────────────────────────────────────────
BODY="🎙️ **Recording Day — $TODAY ($TODAY_DATE)**

**Readiness:**
$SCRIPTS_STATUS
$FFMPEG_STATUS
$CALENDAR_STATUS$([ -n "$CONFLICT_DETAIL" ] && printf '\n%s' "$CONFLICT_DETAIL" || true)
$CONTENT_STATUS$([ -n "$CONTENT_DETAIL" ] && printf '\n%s' "$CONTENT_DETAIL" || true)

**Equipment:**
$EQUIPMENT

\`\`\`bash
python3 ~/content-tools/social-clip/social-clip.py <recording.mp3> \\
  --caption \"Title\" --subtitle \"Out Now\"
\`\`\`
_$(date -u +%Y-%m-%dT%H:%M)Z_"

log "Message built (${#BODY} chars)"

# ── 7. Send or dry-run ────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY RUN — would post to #general:"
  echo "$BODY"
else
  log "Posting to #general ($GENERAL_CHANNEL)..."
  openclaw message send --channel "$GENERAL_CHANNEL" --message "$BODY"
  log "Posted."
fi

log "Done."
