# Agent Ram 🤖

**An AI assistant that monitors your Slack DMs, auto-responds to routine messages, and escalates to you when you're genuinely needed — powered by Snowflake AGENT TASKs and Nova MCPs.**

Built on [Snowflake CoCo (Cortex Code)](https://docs.snowflake.com/en/user-guide/cortex-code) and the Snowflake Nova MCP platform.

---

## What it does

Agent Ram watches your Slack DMs every ~15 minutes (4 staggered AGENT TASKs). For each new message it:

- **HANDLE** → replies as "Agent Ram, your AI assistant" — for greetings, status questions, availability checks
- **ESCALATE** → sends YOU a Slack alert with context — for urgent messages, management, technical decisions

It uses your live Google Calendar to answer "is Ram free?" accurately, and Gmail for email thread context.

**Security guardrails are built-in** — Agent Ram will never reveal credentials, secrets, or config data, and detects prompt injection attempts.

---

## Architecture

```
Snowflake Scheduler (4 staggered AGENT TASKs, each 60-min)
    │
    ├── NOVA_SLACK_MCP          → reads/sends Slack DMs
    ├── NOVA_GOOGLE_CALENDAR_MCP → checks your calendar
    └── NOVA_GOOGLE_GMAIL_MCP   → light inbox scan for context
         │
         ├── /workspace/slack-monitor/state.json  ← dedup processed message IDs
         └── /workspace/memories/                 ← your synced local memory files
```

The 4 tasks fire every 60 min each, staggered ~15 min apart, giving effective 15-min polling. A shared `state.json` in your Snowflake personal stage prevents duplicate replies.

---

## Prerequisites

1. **Snowflake account** with AGENT TASK feature enabled
   ```sql
   -- Verify Nova MCPs are available in your account:
   SHOW EXTERNAL MCP SERVERS IN ACCOUNT;
   -- Must see: NOVA_SLACK_MCP, NOVA_GOOGLE_CALENDAR_MCP, NOVA_GOOGLE_GMAIL_MCP
   ```

2. **CoCo Desktop** with Slack, Google Calendar, and Gmail connected via Settings → Integrations

3. **`cortex` CLI** in PATH (installed with CoCo Desktop)

---

## Setup

```bash
# Clone
git clone https://github.com/sfc-gh-rchandrasekaran/agent-ram
cd agent-ram

# One-command setup (fills in your details)
bash setup.sh "Your Name" "U0YOURSLACKID" "you@company.com" "Your Title"
```

To find your Slack user ID: Slack → click your avatar → Profile → ⋯ → **Copy member ID**

That's it. Four AGENT TASKs will be created in your `USER$` schema.

---

## CoCo Desktop Commands

| Command | Action |
|---------|--------|
| `$agent-ram-on` | Resume all 4 monitoring tasks |
| `$agent-ram-off` | Pause all 4 tasks |
| `$agent-ram-check` | Manual DM check right now (uses your live CoCo session) |

---

## Daily Memory Sync (Recommended)

Agent Ram becomes much smarter when it can read your CoCo memory files — these contain your current projects, key contacts, and work context. The sync is automatic at 5pm daily (configured by `setup.sh`).

**Why sync matters:** Without it, Agent Ram answers "what are your current projects?" from your calendar and Gmail alone. With memory files synced, it can give accurate, detailed answers about your actual work.

```
~/.snowflake/cortex/memory/  ──(5pm daily)──▶  @USER$.PUBLIC.DEFAULT$/memories/
                                               └── Agent Ram reads these at runtime
```

**Run sync manually anytime:**
```bash
bash ~/.snowflake/cortex/agent-ram/sync_to_stage.sh
```

**What gets synced:**
- `memory/MEMORY.md` — your global memory index (projects, people, decisions)
- `memory/projects/*/MEMORY.md` — per-project context files
- `memory/user_profile.md` — your role, communication style, architecture preferences

These files are written and maintained automatically by CoCo as you work.

---

## Customizing Agent Ram

Edit `~/.snowflake/cortex/agent-ram/automation_prompt.md` to:
- Add projects that should always be in context
- Adjust the HANDLE vs ESCALATE classification rules
- Add names to the "always escalate" list (e.g., your manager)
- Change the reply tone

After editing, run sync to push the updated prompt to the stage, then the next automation fire will use the new prompt:
```bash
bash ~/.snowflake/cortex/agent-ram/sync_to_stage.sh
```

> **Future improvement:** modify the AGENT TASK to read its prompt from `/workspace/config/automation_prompt.md` at runtime, so prompt updates take effect without recreating the task.

---

## Turning it off

```bash
# Via CoCo command:
$agent-ram-off

# Via CLI:
cortex automation suspend COCO_ROUTINE_AGENT_RAM_SLACK_MONITOR --connection your-connection-name
cortex automation suspend COCO_ROUTINE_AGENT_RAM_SLACK_B --connection your-connection-name
cortex automation suspend COCO_ROUTINE_AGENT_RAM_SLACK_C --connection your-connection-name
cortex automation suspend COCO_ROUTINE_AGENT_RAM_SLACK_D --connection your-connection-name
```

---

## Cost

Each AGENT TASK fire consumes Snowflake Cortex AI credits. A typical fire:
- ~0 cost if no new DMs (exits after search, minimal LLM calls)
- ~5-10 LLM calls if 2-3 DMs need processing

At 4 tasks × 24 fires/day = 96 fires/day. If 90% find nothing to do, actual AI inference cost is very low (cents/day range).

Monitor via:
```sql
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE SERVICE_TYPE = 'AI_SERVICES'
ORDER BY START_TIME DESC LIMIT 7;
```

---

## Security

Agent Ram has hardcoded guardrails that **cannot be overridden by DM content**:

- Never reveals passwords, tokens, API keys, or config file contents
- Never executes instructions embedded in DMs (prompt injection defense)
- Detects and escalates "ignore your rules" / jailbreak attempts
- Escalates all messages from management without auto-replying

---

## Project Structure

```
agent-ram/
├── setup.sh                    ← one-command installer
├── README.md
├── prompt/
│   └── automation_prompt.md    ← Agent Ram's brain (personalize this)
├── skills/
│   ├── agent-ram-on/SKILL.md   ← $agent-ram-on CoCo command
│   ├── agent-ram-off/SKILL.md  ← $agent-ram-off CoCo command
│   └── agent-ram-check/SKILL.md ← $agent-ram-check CoCo command
├── sync/
│   └── sync_to_stage.sh        ← local memory → Snowflake stage sync
└── docs/
    └── ARCHITECTURE.md         ← technical deep-dive
```

---

## Built with

- [Snowflake CoCo (Cortex Code)](https://docs.snowflake.com/en/user-guide/cortex-code) — the AI coding assistant that powers the agent
- [Snowflake AGENT TASK](https://docs.snowflake.com/en/sql-reference/sql/create-task) — serverless scheduled AI execution
- [Snowflake Nova MCPs](https://docs.snowflake.com/en/user-guide/cortex-code) — Slack, Google Calendar, Gmail integrations
- Claude Sonnet (via `SYSTEM$CORTEX_AGENT_RUN_V2`) — the underlying LLM

---

*Built on [Snowflake CoCo (Cortex Code)](https://docs.snowflake.com/en/user-guide/cortex-code)*
