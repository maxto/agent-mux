# hello-agents

Minimal example of a multi-model session with agent-mux. Three agents — Claude, Codex, and Gemini — each in their own pane, communicating via `tmux-bridge`.

## How it works

You give Claude **one instruction** in natural language. Claude handles everything else: creates the panes, launches the other agents, sends messages, reads replies, reports back to you.

The commands below are what Claude executes — you don't type them.

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
tmux-bridge name "$(tmux-bridge id)" claude
tmux-bridge name %2 codex
tmux-bridge name %3 gemini

# Launch agents
tmux-bridge read codex && tmux-bridge type codex "codex" && tmux-bridge read codex && tmux-bridge keys codex Enter
tmux-bridge read gemini && tmux-bridge type gemini "gemini" && tmux-bridge read gemini && tmux-bridge keys gemini Enter

# Ask each agent their role
tmux-bridge send codex "Hello — load the agent-mux skill. What is your role in this session?"
# [from:codex pane:%2] Ready. Code review, implementation, bug analysis.

tmux-bridge send gemini "Hello — load the agent-mux skill. What is your role in this session?"
# [from:gemini pane:%3] Ready. Adversarial review, alternative approaches, second opinion.
```

## Next steps

- Give Claude a real task and let it delegate to Codex and Gemini
- See the [agent-mux skill](../../skills/agent-mux/SKILL.md) for full tmux-bridge documentation
