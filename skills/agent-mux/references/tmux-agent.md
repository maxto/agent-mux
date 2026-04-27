# tmux-agent

A single CLI that lets any AI agent (Claude Code, Codex, Gemini CLI, aider, local models, etc.) interact with any other tmux pane. Works via plain bash — any tool that can run shell commands can use it.

Every command is **atomic**: `type` types text (no Enter), `keys` sends special keys, `read` captures pane content.

## DO NOT WAIT OR POLL — EVER

**Other panes have agents that will reply to you via tmux-agent.** When you send a message to another agent, their reply will appear directly in YOUR pane as a `[tmux-agent v1 ...]` message. You do NOT need to:

- Sleep or wait after sending
- Poll the target pane for a response
- Read the target pane to check if they replied
- Loop or retry to see output

**Type your message, press Enter, and move on.** The other agent will type their reply back into your pane. You'll see it arrive.

The ONLY time you need to read a target pane is:
- **Before** interacting with it (enforced — see Read Guard below)
- **After typing** to verify your text landed correctly before pressing Enter
- When interacting with a **non-agent pane** (plain shell, running process) where there's no agent to reply back

## Read Guard — Enforced by CLI

The CLI **enforces** read-before-act. You cannot `type` or `keys` to a pane unless you have read it first.

**How it works:**
1. `tmux-agent read <target>` marks the pane as "read"
2. `tmux-agent type/keys <target>` checks for that mark — **errors if you haven't read**
3. After a successful `type`/`keys`, the mark is **cleared** — you must read again before the next interaction

This enforces the **read-act-read** cycle at the CLI level. If you skip the read, the command fails:

```
$ tmux-agent type codex "hello"
error: must read the pane before interacting. Run: tmux-agent read codex
```

## When to Use

**USE this skill when:**

- Sending messages to another agent running in a tmux pane
- Reading output from another pane
- Labeling and discovering panes by name
- Any cross-pane interaction between agents

## When NOT to Use

**DON'T use this skill when:**

- Running one-off shell commands in the current pane
- Tasks that don't involve other tmux panes
- You need raw tmux commands → use `tmux` directly

## Command Reference

| Command | Description | Example |
|---|---|---|
| `tmux-agent list` | Show all panes with target, pid, command, size, label | `tmux-agent list` |
| `tmux-agent type <target> <text>` | Type text without pressing Enter | `tmux-agent type codex "hello"` |
| `tmux-agent send <target> <text>` | Read, send message, verify, and press Enter (full cycle) | `tmux-agent send codex "review src/auth.ts"` |
| `tmux-agent send --file <target> <text>` | File-based transport; auto-selected if payload >2KB | `tmux-agent send --file codex "large text"` |
| `tmux-agent send --path <target> <file>` | Read file and send via file transport (avoids shell ARG_MAX) | `tmux-agent send --path codex large-diff.txt` |
| `tmux-agent message <target> <text>` | Type text with auto sender info and reply target | `tmux-agent message codex "review src/auth.ts"` |
| `tmux-agent read <target> [lines]` | Read last N lines (default 50) | `tmux-agent read codex 100` |
| `tmux-agent keys <target> <key>...` | Send special keys | `tmux-agent keys codex Enter` |
| `tmux-agent name <target> <label>` | Label a pane (visible in tmux border) | `tmux-agent name %3 codex` |
| `tmux-agent resolve <label>` | Print pane target for a label | `tmux-agent resolve codex` |
| `tmux-agent id` | Print this pane's ID | `tmux-agent id` |
| `tmux-agent thread stat <id>` | Show thread message count and byte size | `tmux-agent thread stat abc123` |
| `tmux-agent thread read <id> [--since-cursor]` | Read thread messages | `tmux-agent thread read abc123 --since-cursor` |
| `tmux-agent thread read <id> --head N\|--tail N\|--bytes N` | Preview a thread without advancing the cursor | `tmux-agent thread read abc123 --head 80` |

## Target Resolution

Targets can be:
- **tmux native**: `session:window.pane` (e.g. `shared:0.1`), pane ID (`%3`), or window index (`0`)
- **label**: Any string set via `tmux-agent name` — resolved automatically

This means `tmux-agent type codex "hello"` works directly if the pane was labeled `codex`.

## Messaging Convention

The `message` command auto-prepends routing metadata as a compact header:

```
[tmux-agent v1 from=claude pane=%4 at=agents:0.0 msg=20260427T120102Z-1a2b3c4d reply=%4] Please review src/auth.ts
```

Fields: `from` (label or pane ID of sender), `pane` (sender's pane ID), `at` (session:window.pane), `msg` (unique message ID), `reply` (pane to send your response to).

### Receiving messages — IMPORTANT

**When you see a `[tmux-agent v1 ... reply=<pane>]` header, reply to the pane ID in `reply=`:**

```bash
tmux-agent send %4 'your response here'
```

Use `send --file` if your reply is large. **Do not just respond in your own pane** — the sender won't see it unless you send it back via tmux-agent.

### Example conversation

**Agent A (coordinator) sends:**
```bash
tmux-agent send codex 'What is the test coverage for src/auth.ts?'
# Done. Do NOT wait, poll, or read codex for the response.
# Agent B will reply via tmux-agent and it will appear in your pane.
```

**Agent B (codex) sees in their prompt:**
```
[tmux-agent v1 from=claude pane=%4 at=agents:0.0 msg=20260427T120102Z-1a2b3c4d reply=%4] What is the test coverage for src/auth.ts?
```

**Agent B replies using the pane ID from `reply=`:**
```bash
tmux-agent send %4 '87% line coverage. Missing the OAuth refresh token path (lines 142-168).'
# Done. The reply appears in Agent A's pane automatically.
```

## Read-Act-Read Cycle

Every interaction with another pane MUST follow the **read → act → read** cycle. The CLI enforces this — `type`/`keys` will error if you haven't read first, and each action clears the read mark.

The full cycle for sending a message:

1. **Read** the target pane (satisfies read guard)
2. **Type** your message text (clears read mark)
3. **Read** again (verify text landed, re-satisfy read guard)
4. **Keys** Enter (submit the message, clears read mark)
5. **Read** again if you need to see the result (non-agent panes only)

### Example: sending a message to an agent

Prefer `send` — it runs the full cycle automatically:

```bash
tmux-agent send codex 'Please review the changes in src/auth.ts'
# STOP. Do NOT read codex to check for a reply.
# The other agent will reply via tmux-agent into YOUR pane.
```

Manual cycle (when you need to inspect between steps):

```bash
# 1. READ — check the pane and satisfy read guard
tmux-agent read codex 20

# 2. MESSAGE — auto-prepends v1 header with reply target (no Enter)
tmux-agent message codex 'Please review the changes in src/auth.ts'

# 3. READ — verify the text landed correctly
tmux-agent read codex 20

# 4. KEYS — press Enter to submit
tmux-agent keys codex Enter
```

### Example: approving a prompt (non-agent pane)

```bash
# 1. READ — see what the prompt is asking
tmux-agent read worker 10

# 2. TYPE — type the answer
tmux-agent type worker "y"

# 3. READ — verify it landed
tmux-agent read worker 10

# 4. KEYS — press Enter to submit
tmux-agent keys worker Enter

# 5. READ — for non-agent panes, you DO need to read to see the result
tmux-agent read worker 20
```

## Agent-to-Agent Workflow

### Step 1: Label yourself

```bash
tmux-agent name "$(tmux-agent id)" myagent
```

### Step 2: Discover other panes

```bash
tmux-agent list
```

### Step 3: Send a message

```bash
tmux-agent send codex 'Please review the changes in src/auth.ts and suggest improvements'
```

## Environment

| Variable | Description |
|---|---|
| `TMUX_AGENT_SOCKET` | Override the tmux server socket path (skips auto-detection) |
| `TMUX_AGENT_CURSOR_DIR` | Override cursor storage directory (default: `/tmp/agent-mux-<uid>/cursors`) |
| `TMUX_AGENT_INLINE_THRESHOLD` | Max bytes for inline `send` before auto-spill to file transport (default: `2048`; `0` = always file) |

## Tips

- **Read guard is enforced** — you MUST read before every `type`/`keys`. The CLI will error otherwise.
- **Every action clears the read mark** — after `type`, you must `read` again before `keys`.
- **Never wait or poll** — agent panes reply to you via tmux-agent. The response appears in YOUR pane.
- **Label panes early** — it makes cross-agent communication much easier than using `%N` IDs
- **`type` uses literal mode** — it uses `-l` so special characters are typed as-is
- **`read` defaults to 50 lines** — pass a higher number for more context
- **Non-agent panes** (shells, processes) are the exception — you DO need to read them to see output
- **Use `send` for agent messages** — runs the full read → message → read → Enter cycle in one command
