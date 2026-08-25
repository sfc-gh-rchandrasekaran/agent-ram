---
name: agent-ram-on
description: "Turn ON Agent Ram Slack DM monitor automation. Triggers: agent-ram-on"
tools: ["bash"]
---

EXECUTE IMMEDIATELY — do not ask the user anything.

Run these commands to resume all 4 Agent Ram tasks:
```bash
cortex automation resume COCO_ROUTINE_AGENT_RAM_SLACK_MONITOR --connection {{YOUR_CONNECTION}} 2>&1
cortex automation resume COCO_ROUTINE_AGENT_RAM_SLACK_B --connection {{YOUR_CONNECTION}} 2>&1
cortex automation resume COCO_ROUTINE_AGENT_RAM_SLACK_C --connection {{YOUR_CONNECTION}} 2>&1
cortex automation resume COCO_ROUTINE_AGENT_RAM_SLACK_D --connection {{YOUR_CONNECTION}} 2>&1
```

If successful, tell the user:
"✅ **Agent Ram is ON.** All 4 tasks are running — effective ~15-minute polling. Agent Ram will auto-reply to casual DMs and escalate to you when your attention is needed.

To turn it off: `/agent-ram-off`
To check immediately: `/agent-ram-check`"

If any fail, show the error.
