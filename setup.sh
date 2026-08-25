#!/bin/bash
# Agent Ram — One-command setup
# Usage: bash setup.sh <YOUR_NAME> <YOUR_SLACK_ID> <YOUR_EMAIL> <YOUR_TITLE>
# Example: bash setup.sh "Jane Smith" "U07ABC123" "jane@snowflake.com" "Senior SE"
#
# Prerequisites:
#   - CoCo Desktop installed (https://docs.snowflake.com/en/user-guide/cortex-code)
#   - Snowflake account with Nova MCPs available (run: SHOW EXTERNAL MCP SERVERS IN ACCOUNT)
#   - Slack, Google Calendar, Gmail connected via CoCo Desktop settings
#   - cortex CLI in PATH (comes with CoCo Desktop)

set -euo pipefail

MY_NAME="${1:-}"
MY_SLACK_ID="${2:-}"
MY_EMAIL="${3:-}"
MY_TITLE="${4:-Solution Architect}"
SNOWHOUSE_CONNECTION="${5:-snowhouse}"

if [[ -z "$MY_NAME" || -z "$MY_SLACK_ID" || -z "$MY_EMAIL" ]]; then
  echo "Usage: bash setup.sh \"Your Name\" \"U0SLACKID\" \"you@snowflake.com\" \"Your Title\""
  echo ""
  echo "To find your Slack user ID:"
  echo "  1. Open Slack → click your avatar → Profile"
  echo "  2. Click the three dots (⋯) → Copy member ID"
  exit 1
fi

INSTALL_DIR="$HOME/.snowflake/cortex/agent-ram"
SKILLS_DIR="$HOME/.snowflake/cortex/skills"
PLIST_LABEL="com.$(echo "$MY_NAME" | tr '[:upper:] ' '[:lower:]-').agent-ram-sync"

echo "Setting up Agent Ram for: $MY_NAME ($MY_SLACK_ID)"
echo ""

# ── Step 1: Create directories ──────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
mkdir -p "$SKILLS_DIR/agent-ram-on"
mkdir -p "$SKILLS_DIR/agent-ram-off"
mkdir -p "$SKILLS_DIR/agent-ram-check"

# ── Step 2: Personalize the prompt ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sed \
  -e "s/Ramkumar Chandrasekaran/$MY_NAME/g" \
  -e "s/r\.chandrasekaran@snowflake\.com/$MY_EMAIL/g" \
  -e "s/U07881PANCE/$MY_SLACK_ID/g" \
  -e "s/Principal Solution Architect at Snowflake/$MY_TITLE at Snowflake/g" \
  "$SCRIPT_DIR/prompt/automation_prompt.md" > "$INSTALL_DIR/automation_prompt.md"

echo "✓ Personalized prompt saved to $INSTALL_DIR/automation_prompt.md"

# ── Step 3: Install CoCo skills ─────────────────────────────────────────────
for skill in agent-ram-on agent-ram-off agent-ram-check; do
  cp "$SCRIPT_DIR/skills/$skill/SKILL.md" "$SKILLS_DIR/$skill/SKILL.md"
  # Substitute user-specific values in skills
  sed -i.bak \
    -e "s/COCO_ROUTINE_AGENT_RAM_SLACK_MONITOR/COCO_ROUTINE_AGENT_RAM_SLACK_MONITOR/g" \
    -e "s/--connection snowhouse/--connection $SNOWHOUSE_CONNECTION/g" \
    "$SKILLS_DIR/$skill/SKILL.md"
  rm -f "$SKILLS_DIR/$skill/SKILL.md.bak"
  cortex skill add "$SKILLS_DIR/$skill" 2>/dev/null || true
done

echo "✓ CoCo skills installed: \$agent-ram-on, \$agent-ram-off, \$agent-ram-check"

# ── Step 4: Install sync script ─────────────────────────────────────────────
sed \
  -e "s|RCHANDRASEKARAN|$(echo "$MY_EMAIL" | cut -d@ -f1 | tr '.' '_' | tr '[:lower:]' '[:upper:]')|g" \
  -e "s|--connection snowhouse|--connection $SNOWHOUSE_CONNECTION|g" \
  "$SCRIPT_DIR/sync/sync_to_stage.sh" > "$INSTALL_DIR/sync_to_stage.sh"
chmod +x "$INSTALL_DIR/sync_to_stage.sh"

echo "✓ Sync script saved to $INSTALL_DIR/sync_to_stage.sh"

# ── Step 5: Install end-of-day launchd job (macOS only) ─────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
  PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
  cat > "$PLIST_PATH" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$INSTALL_DIR/sync_to_stage.sh</string>
    </array>
    <!-- Run at 5pm daily (end of work day) -->
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>17</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/sync_stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/sync_stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>
</dict>
</plist>
PLIST_EOF

  launchctl load "$PLIST_PATH" 2>/dev/null || true
  echo "✓ End-of-day sync scheduled: runs at 5pm daily"
fi

# ── Step 6: Create the Snowflake automation ─────────────────────────────────
echo ""
echo "Creating Snowflake AGENT TASKs (4 staggered for ~15-min effective polling)..."

for suffix in "" "_B" "_C" "_D"; do
  cortex automation create \
    --name "AGENT_RAM_SLACK_MONITOR$suffix" \
    --schedule "every 60 minutes" \
    --mcp SNOWFLAKE_INTELLIGENCE.MCP.NOVA_SLACK_MCP \
    --mcp SNOWFLAKE_INTELLIGENCE.MCP.NOVA_GOOGLE_CALENDAR_MCP \
    --mcp SNOWFLAKE_INTELLIGENCE.MCP.NOVA_GOOGLE_GMAIL_MCP \
    --prompt-file "$INSTALL_DIR/automation_prompt.md" \
    --timezone "America/Chicago" \
    --connection "$SNOWHOUSE_CONNECTION" 2>/dev/null \
    && echo "  ✓ AGENT_RAM_SLACK_MONITOR$suffix" \
    || echo "  ✗ AGENT_RAM_SLACK_MONITOR$suffix (may already exist)"
  sleep 2
done

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Agent Ram is live for $MY_NAME!"
echo "║                                                      ║"
echo "║  Commands in CoCo Desktop:                          ║"
echo "║    \$agent-ram-on    → resume all tasks              ║"
echo "║    \$agent-ram-off   → pause all tasks               ║"
echo "║    \$agent-ram-check → manual DM check now           ║"
echo "║                                                      ║"
echo "║  Memory sync: runs daily at 5pm to Snowflake stage  ║"
echo "║  Run now: bash $INSTALL_DIR/sync_to_stage.sh        ║"
echo "╚══════════════════════════════════════════════════════╝"
