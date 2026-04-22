# hello-agents

Minimal example of a multi-model session with agent-mux. Three agents — Claude, Codex, and Gemini — each in their own pane, communicating via `tmux-agent`.

## How it works

You give the coordinator agent **one instruction** in natural language. It handles everything else: creates the panes, launches the other agents, sends messages, reads replies, reports back to you.

The commands below are what the coordinator executes — you don't type them.

## Prerequisites

- agent-mux installed — `curl -fsSL https://maxto.github.io/agent-mux/install.sh | bash`
- Claude Code, Codex CLI, and Gemini CLI in your PATH
- A tmux session running — `tmux new-session -s agents`

## Run it

Open Claude Code in your tmux session and send this message:

> Set up a 3-agent session. Launch Codex and Gemini in new panes, then ask each one to describe their role in this session.

Claude will execute:

```bash
# Create panes and label them
tmux split-window -h
tmux split-window -v
tmux-agent name "$(tmux-agent id)" claude
tmux-agent name %2 codex
tmux-agent name %3 gemini

# Launch agents
tmux-agent read codex && tmux-agent type codex "codex" && tmux-agent read codex && tmux-agent keys codex Enter
tmux-agent read gemini && tmux-agent type gemini "gemini" && tmux-agent read gemini && tmux-agent keys gemini Enter

# Ask each agent their role
tmux-agent send codex "Hello — load the agent-mux skill. What is your role in this session?"
# [from:codex pane:%2] Ready. Code review, implementation, bug analysis.

tmux-agent send gemini "Hello — load the agent-mux skill. What is your role in this session?"
# [from:gemini pane:%3] Ready. Adversarial review, alternative approaches, second opinion.
```

## Next steps

- Give Claude a real task and let it delegate to Codex and Gemini
- See the [agent-mux skill](../../skills/agent-mux/SKILL.md) for full tmux-agent documentation
