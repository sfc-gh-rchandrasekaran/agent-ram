# Architecture Deep-Dive

## How AGENT TASKs Work

A Snowflake AGENT TASK is a serverless scheduled task that runs `SYSTEM$CORTEX_AGENT_RUN_V2()`. Unlike regular Snowflake Tasks (which run SQL or stored procedures), an AGENT TASK boots a full CoCo (Cortex Code) agent in an ephemeral sandbox:

```
Snowflake Scheduler
    │  fires every 60 min
    ▼
SELECT SYSTEM$CORTEX_AGENT_RUN_V2('{...json...}', true)
    │
    ▼
Snowflake spins up ephemeral container
    ├── mounts USER$.PUBLIC.DEFAULT$ → /workspace
    ├── initializes MCP clients (Slack, Calendar, Gmail)
    └── starts LLM agentic loop with your prompt
```

The `true` second argument means headless execution (no interactive prompts).

## The MCP Authentication Chain

The Nova MCPs are registered in Snowflake as External MCP Servers:

```sql
SHOW EXTERNAL MCP SERVERS IN ACCOUNT;
-- NOVA_SLACK_MCP → api_integration: NOVA_SLACK
-- NOVA_GOOGLE_CALENDAR_MCP → api_integration: NOVA_GOOGLE_CALENDAR
-- NOVA_GOOGLE_GMAIL_MCP → api_integration: NOVA_GOOGLE_GMAIL
```

Each has a Snowflake API Integration that handles auth:

```
Sandbox calls mcp tool (e.g., slack_send_message)
    │
    ▼
HTTP POST to Nova MCP endpoint
    https://snowflake.mcp.nova.cortex.snowflake.app/v2/profile/default-profile/slack-remote/mcp
    │
    ▼  (Snowflake API Integration validates session)
Nova MCP Gateway
    │  (maps Snowflake identity → user's OAuth token)
    ▼
Slack API (chat.postMessage)
```

The task runs as `execute_as_user: <YOUR_SNOWFLAKE_USER>`, so Nova uses YOUR OAuth token — Agent Ram acts on your behalf.

## The Personal Workspace Stage

`@USER$<YOUR_USER>.PUBLIC.DEFAULT$` is your personal Snowflake stage, automatically provisioned by Snowflake. It's backed by the same object storage (S3/Azure/GCS) as all Snowflake stages, but access is restricted to your user.

When mounted at `/workspace` inside the sandbox:
- Reads are lazy (fetched on-demand from object storage, not pre-synced)
- Writes are atomic PUTs (whole file lands or nothing does)
- No filesystem semantics (no locking, no partial writes)
- Stage is S3-co-located with your Snowflake account (same region = fast)

## Deduplication with state.json

Four tasks share one state file. The `NO_OVERLAP` policy prevents concurrent execution of the same task, but different tasks CAN run simultaneously. The state.json prevents duplicate replies:

```
Task A fires at 11:00:00 → reads state.json → processes Hari's DM → writes updated state.json
Task B fires at 11:00:02 → reads state.json → Hari's message ID already in processed_ids → skips
```

Race condition risk: if two tasks fire at exactly the same time and read state.json before either writes, both could process the same message. This is rare in practice (task execution takes 30-60 seconds) and the worst outcome is a duplicate reply (not a security or data integrity issue).

## The 5pm Memory Sync

```
5pm (launchd) → sync_to_stage.sh runs
    │
    ├── find ~/.snowflake/cortex/memory/ -name "*.md"
    │   └── snow stage copy each file → @USER$.PUBLIC.DEFAULT$/memories/
    │
    └── generate current_activity.md
        ├── git log --since="7 days ago" (active repos)
        ├── recently modified files
        └── cat memory/MEMORY.md (project index)
        └── snow stage copy → @USER$.PUBLIC.DEFAULT$/activity/current_activity.md

Next automation fire:
    reads /workspace/memories/MEMORY.md → knows your projects
    reads /workspace/activity/current_activity.md → knows recent activity
```

## Cost Model

Each AGENT TASK fire:
- Consumes Cortex AI credits proportional to tokens processed
- No warehouse needed (serverless AGENT TASKs)
- Typical fire with no new DMs: ~1-2 LLM calls (search + brief reasoning) = minimal
- Typical fire with 2-3 DMs to handle: ~8-12 LLM calls = still low cost

4 tasks × 24 fires/day = 96 fires/day total. If 85% find nothing to do and exit early, real cost is ~14 fires/day with meaningful work.

Monitor:
```sql
SELECT DATE_TRUNC('day', START_TIME) as day,
       SUM(CREDITS_USED) as credits
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE SERVICE_TYPE = 'AI_SERVICES'
  AND START_TIME > DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY 1 ORDER BY 1 DESC;
```
