#!/bin/bash
# Sync local context to Snowflake workspace stage for Agent Ram
# Runs every 30 min via launchd. Uploads memories + current activity snapshot.

set -euo pipefail

STAGE="@USER\$RCHANDRASEKARAN.PUBLIC.\"DEFAULT\$\""
CONNECTION="snowhouse"
LOG="$HOME/.snowflake/cortex/slack-monitor/sync.log"
ACTIVITY_FILE="/tmp/agent_ram_activity.md"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Rotate log
if [ -f "$LOG" ] && [ $(wc -l < "$LOG") -gt 300 ]; then
  tail -100 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
fi

log "Starting sync..."

# ── Step 1: Sync memory files ──────────────────────────────────────────────
MEMORIES_DIR="$HOME/.snowflake/cortex/memory"
if [ -d "$MEMORIES_DIR" ]; then
  # Upload all .md files recursively, preserving folder structure
  find "$MEMORIES_DIR" -name "*.md" | while read -r file; do
    relative="${file#$MEMORIES_DIR/}"
    snow stage copy "$file" "$STAGE/memories/$relative" \
      --connection "$CONNECTION" --overwrite 2>/dev/null || true
  done
  log "Memory files synced."
else
  log "No memories dir found, skipping."
fi

# ── Step 2: Build current_activity.md ─────────────────────────────────────
{
  echo "# Ram's Current Activity Snapshot"
  echo "Generated: $(date)"
  echo ""

  # Active git repos with recent commits
  echo "## Active Git Repositories (last 7 days)"
  for dir in "$HOME/Desktop/Cursor"/*/; do
    if [ -d "$dir/.git" ]; then
      repo=$(basename "$dir")
      recent=$(git -C "$dir" log --oneline --since="7 days ago" 2>/dev/null | head -3)
      if [ -n "$recent" ]; then
        branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "unknown")
        echo "### $repo (branch: $branch)"
        echo "$recent"
        echo ""
      fi
    fi
  done

  # Currently open/modified files (last 24h)
  echo "## Recently Modified Files (last 24h)"
  find "$HOME/Desktop/Cursor" -name "*.py" -o -name "*.sql" -o -name "*.md" -o -name "*.yaml" -o -name "*.yml" \
    2>/dev/null | xargs ls -t 2>/dev/null | head -20 | while read -r f; do
    if [ $(find "$f" -newer "$HOME/.snowflake/cortex/slack-monitor/state.json" 2>/dev/null | wc -l) -gt 0 ]; then
      echo "- $(basename "$f") ($(dirname "$f" | sed "s|$HOME|~|"))"
    fi
  done 2>/dev/null || true

  # CoCo recent session summaries (last 3)
  echo ""
  echo "## Recent CoCo Session Activity"
  CONV_DIR="$HOME/.snowflake/cortex/conversations"
  if [ -d "$CONV_DIR" ]; then
    find "$CONV_DIR" -name "*.json" -newer "$HOME/.snowflake/cortex/slack-monitor/state.json" 2>/dev/null \
      | head -3 | while read -r f; do
        session_id=$(basename "$(dirname "$f")")
        echo "- Session: $session_id"
      done
  fi

  echo ""
  echo "## Project Memory Index"
  if [ -f "$MEMORIES_DIR/MEMORY.md" ]; then
    cat "$MEMORIES_DIR/MEMORY.md"
  fi

} > "$ACTIVITY_FILE" 2>/dev/null

# Upload activity file
snow stage copy "$ACTIVITY_FILE" "$STAGE/activity/current_activity.md" \
  --connection "$CONNECTION" --overwrite 2>/dev/null \
  && log "Activity snapshot synced." \
  || log "Activity snapshot upload failed (non-fatal)."

log "Sync complete."
