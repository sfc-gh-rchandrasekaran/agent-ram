---
name: agent-ram-off
description: "Turn OFF Agent Ram Slack DM monitor automation. Triggers: agent-ram-off"
tools: ["bash"]
---

EXECUTE IMMEDIATELY — do not ask the user anything.

Run these commands to suspend all 4 Agent Ram tasks:
```bash
cortex automation suspend COCO_ROUTINE_AGENT_RAM_SLACK_MONITOR --connection snowhouse 2>&1
cortex automation suspend COCO_ROUTINE_AGENT_RAM_SLACK_B --connection snowhouse 2>&1
cortex automation suspend COCO_ROUTINE_AGENT_RAM_SLACK_C --connection snowhouse 2>&1
cortex automation suspend COCO_ROUTINE_AGENT_RAM_SLACK_D --connection snowhouse 2>&1
```

If successful, tell the user:
"⏸️ **Agent Ram is OFF.** All 4 tasks have been paused. Your DMs will no longer receive auto-replies.

To turn it back on: `/agent-ram-on`"

If any fail, show the error.
