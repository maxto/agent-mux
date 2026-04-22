---
name: agent-mux
description: Control tmux panes and communicate between AI agents. Use this skill whenever the user mentions tmux panes, cross-pane communication, sending messages to other agents, reading other panes, managing tmux sessions, or interacting with processes running in tmux. Includes tmux-agent CLI for agent-to-agent messaging and raw tmux commands for direct session control.
metadata:
  { "openclaw": { "emoji": "🖥️", "os": ["darwin", "linux"], "requires": { "bins": ["tmux", "tmux-agent"] } } }
---

# agent-mux

Tmux pane control and cross-pane agent communication. Use `tmux-agent` (the high-level CLI) for all cross-pane interactions. Fall back to raw tmux commands only when you need low-level control.

## tmux-agent — Cross-Pane Communication

A CLI that lets any AI agent interact with any other tmux pane. Works via plain bash. Every command is **atomic**: `type` types text (no Enter), `keys` sends special keys, `read` captures pane content.

### DO NOT WAIT OR POLL

Other panes have agents that will reply to you via tmux-agent. Their reply appears directly in YOUR pane as a `[tmux-agent from:...]` message. Do not sleep, poll, read the target pane for a response, or loop. Type your message, press Enter, and move on.

The ONLY time you read a target pane is:
- **Before** interacting with it (enforced by the read guard)
- **After typing** to verify your text landed before pressing Enter
- When interacting with a **non-agent pane** (plain shell, running process)

### Read Guard

The CLI enforces read-before-act. You cannot `type` or `keys` to a pane unless you have read it first.

1. `tmux-agent read <target>` marks the pane as "read"
2. `tmux-agent type/keys <target>` checks for that mark — errors if you haven't read
3. After a successful `type`/`keys`, the mark is cleared — you must read again before the next interaction

```
$ tmux-agent type codex "hello"
error: must read the pane before interacting. Run: tmux-agent read codex
```

### Command Reference

| Command | Description | Example |
|---|---|---|
| `tmux-agent list` | Show all panes with target, pid, command, size, label | `tmux-agent list` |
| `tmux-agent type <target> <text>` | Type text without pressing Enter | `tmux-agent type codex "hello"` |
| `tmux-agent send <target> <text>` | Read, send message, verify, and press Enter (full cycle) | `tmux-agent send codex "review src/auth.ts"` |
| `tmux-agent message <target> <text>` | Type text with auto sender info and reply target | `tmux-agent message codex "review src/auth.ts"` |
| `tmux-agent read <target> [lines]` | Read last N lines (default 50) | `tmux-agent read codex 100` |
| `tmux-agent keys <target> <key>...` | Send special keys | `tmux-agent keys codex Enter` |
| `tmux-agent name <target> <label>` | Label a pane (visible in tmux border) | `tmux-agent name %3 codex` |
| `tmux-agent resolve <label>` | Print pane target for a label | `tmux-agent resolve codex` |
| `tmux-agent id` | Print this pane's ID | `tmux-agent id` |
| `tmux-agent doctor` | Diagnose tmux connectivity issues | `tmux-agent doctor` |

### Target Resolution

Targets can be:
- **tmux native**: `session:window.pane` (e.g. `shared:0.1`), pane ID (`%3`), or window index (`0`)
- **label**: Any string set via `tmux-agent name` — resolved automatically

### Sending a Message

Use `send` for agent-to-agent messages — it runs the full cycle in one command:

```bash
tmux-agent send codex 'Please review src/auth.ts'
```

Both intermediate pane reads are printed to stdout. Do NOT poll or read the target pane after sending — the target agent types its reply directly into your pane via tmux-agent.

**After sending:** the target pane's read guard is cleared. Your next `send` to the same target starts a fresh cycle automatically.

### How It Works (Read-Act-Read)

`send` executes four steps internally. Use the manual cycle when you need to inspect the pane between steps:

```bash
tmux-agent read codex 20                    # 1. READ — satisfy read guard
tmux-agent message codex 'Please review src/auth.ts'
                                             # 2. MESSAGE — auto-prepends sender info, no Enter
tmux-agent read codex 20                    # 3. READ — verify text landed
tmux-agent keys codex Enter                 # 4. KEYS — submit
```

**Approving a prompt (non-agent pane):**
```bash
tmux-agent read worker 10                   # 1. READ — see the prompt
tmux-agent type worker "y"                  # 2. TYPE
tmux-agent read worker 10                   # 3. READ — verify
tmux-agent keys worker Enter                # 4. KEYS — submit
tmux-agent read worker 20                   # 5. READ — see the result
```

### Messaging Convention

The `message` command auto-prepends sender info and location:

```
[tmux-agent from:claude pane:%4 at:3:0.0 - load the agent-mux skill to reply] Please review src/auth.ts
```

The receiver gets: who sent it (`from`), the exact pane to reply to (`pane`), and the session/window location (`at`). When you see this header, reply using tmux-agent to the pane ID from the header.

### Agent-to-Agent Workflow

```bash
# 1. Label yourself
tmux-agent name "$(tmux-agent id)" claude

# 2. Discover other panes
tmux-agent list

# 3. Send a message
tmux-agent send codex 'Please review the changes in src/auth.ts'
```

### Example Conversation

**Agent A (coordinator) sends:**
```bash
tmux-agent send codex 'What is the test coverage for src/auth.ts?'
```

**Agent B (codex) sees in their prompt:**
```
[tmux-agent from:claude pane:%4 at:3:0.0 - load the agent-mux skill to reply] What is the test coverage for src/auth.ts?
```

**Agent B replies using the pane ID from the header:**
```bash
tmux-agent send %4 '87% line coverage. Missing the OAuth refresh token path (lines 142-168).'
```

---

## Raw tmux Commands

Use these when you need direct tmux control beyond what tmux-agent provides — session management, window navigation, creating panes, or low-level scripting.

### Capture Output

```bash
tmux capture-pane -t shared -p | tail -20    # Last 20 lines
tmux capture-pane -t shared -p -S -          # Entire scrollback
tmux capture-pane -t shared:0.0 -p           # Specific pane
```

### Send Keys

```bash
tmux send-keys -t shared -l -- "text here"   # Type text (literal mode)
tmux send-keys -t shared Enter               # Press Enter
tmux send-keys -t shared Escape              # Press Escape
tmux send-keys -t shared C-c                 # Ctrl+C
tmux send-keys -t shared C-d                 # Ctrl+D (EOF)
```

For interactive TUIs, split text and Enter into separate sends:
```bash
tmux send-keys -t shared -l -- "Please apply the patch"
sleep 0.1
tmux send-keys -t shared Enter
```

### Panes and Windows

```bash
# Create panes (prefer over new windows)
tmux split-window -h -t SESSION              # Horizontal split
tmux split-window -v -t SESSION              # Vertical split
tmux select-layout -t SESSION tiled          # Re-balance

# Navigate
tmux select-window -t shared:0
tmux select-pane -t shared:0.1
tmux list-windows -t shared
```

### Session Management

```bash
tmux list-sessions
tmux new-session -d -s newsession
tmux kill-session -t sessionname
tmux rename-session -t old new
```

### Agent Patterns

```bash
# Check if a pane needs input
tmux capture-pane -t worker-3 -p | tail -10 | grep -E "❯|Yes.*No|proceed|permission"

# Approve a prompt
tmux send-keys -t worker-3 'y' Enter

# Check all panes in a session
for pane in $(tmux list-panes -t agents -F '#{pane_id}'); do
  echo "=== $pane ==="
  tmux capture-pane -t $pane -p 2>/dev/null | tail -5
done
```

## Tips

- **Read guard is enforced** — you MUST read before every `type`/`keys`
- **Every action clears the read mark** — after `type`, read again before `keys`
- **Never wait or poll** — agent panes reply via tmux-agent into YOUR pane
- **Label panes early** — easier than using `%N` IDs
- **`type` uses literal mode** — special characters are typed as-is
- **`read` defaults to 50 lines** — pass a higher number for more context
- **Non-agent panes** are the exception — you DO need to read them to see output
- Use `capture-pane -p` to print to stdout (essential for scripting)
- Target format: `session:window.pane` (e.g., `shared:0.0`)

## Loading this skill in other agents

| Agent | How to load |
|---|---|
| Claude Code | `/agent-mux` (after `agent-mux install` in your project) |
| Codex | `/init` — reads `SKILL.md` automatically |
| Gemini CLI | `@.claude/skills/agent-mux/SKILL.md` |
| aider | `/add .claude/skills/agent-mux/SKILL.md` |
| Any agent | Paste or include `SKILL.md` in system prompt |

## Environment

| Variable | Description |
|---|---|
| `TMUX_AGENT_SOCKET` | Override the tmux server socket path (skips auto-detection) |
