# agent-mux

agent-mux is tmux for humans and AI agents working in the same terminal.

*A local multi-agent coordination layer for terminal-native AI coding workflows.*

- **Humans get a friendlier tmux**: Alt-key navigation, mouse support, labeled panes, and no prefix-key muscle memory required.
- **Agents get a shared control layer**: `tmux-agent` lets Claude Code, Codex, Gemini CLI, local models, and other bash-capable agents read panes, send input, reply across panes, and hand off large payloads without pasting them inline.
- **Teams get parallel model workflows**: run multiple agents on the same repo for implementation, review, testing, and cross-checking without leaving tmux.

agent-mux is not a memory system, RAG layer, or codebase knowledge graph. It
installs the tmux workspace, `tmux-agent` protocol, and neutral skill docs; use
your agents' own memory systems for durable project facts.

## Why agent-mux?

Without it:

- copy-paste between terminal windows to hand off diffs, logs, or prompts
- large payloads bloat the receiver's prompt context immediately
- no shared routing — agents can't address or reply to each other
- each agent works in isolation with no awareness of what others are doing

With agent-mux:

- agents send messages across panes with `tmux-agent send` — no copy-paste
- large handoffs stay on disk via thread transport; the receiver loads them only when needed
- replies route back to the sender automatically via pane ID
- Claude Code orchestrates (the `/agent-mux` skill auto-loads there); other agents (Codex, Gemini, DeepSeek, local models…) participate as workers

Large handoffs between agents no longer inflate the prompt. When a payload exceeds the inline threshold (default 2KB), `tmux-agent send` automatically switches to thread transport: the receiver sees only a compact ping, and the full content stays on disk until they explicitly call `tmux-agent thread read`. The threshold is configurable via `TMUX_AGENT_INLINE_THRESHOLD` — set it to `0` to always use file transport regardless of size.

## Quickstart

```bash
# 1. Install once per machine (also installs tmux if missing, and the
#    user-wide Claude skill so /agent-mux works in EVERY folder)
curl -fsSL https://maxto.github.io/agent-mux/install.sh | bash
source ~/.bashrc   # or open a new terminal

# 2. Create a session (defaults to a single-pane session named 'agent'),
#    then enter it
agent-mux session start
agent-mux attach agent

# 3. In Claude Code (any folder, no per-project install needed):
/agent-mux
```

Claude now knows how to use `tmux-agent` to talk to other panes, launch agents, and coordinate work. `/agent-mux` is available in any project because the skill is installed user-wide by the `curl | bash` step — you do not re-run anything per project for Claude.

For a multi-agent layout, pass explicit labels (and optional per-pane commands). `session start` always creates a **new detached session** and never splits your current window; it errors if the name is already taken:

```bash
agent-mux session start \
  --name agents \
  --labels coordinator,codex,gemini \
  --cmds claude,codex,gemini
agent-mux attach agents
```

To let any non-Claude agent (Codex, Gemini, local models, …) in a repo discover `tmux-agent`, drop the neutral skill into that project:

```bash
cd your-project
agent-mux install   # writes skills/agent-mux/ for non-Claude agents
```

## Example

Three agents, one project. One coordinator agent handles everything else.

> "Set up a 3-agent session with Codex and Gemini. Ask each one their role."

The coordinator sets up the panes, launches the agents, and coordinates via `tmux-agent`:

```
[from:codex] Ready. Code review, implementation, bug analysis.
[from:gemini] Ready. Adversarial review, alternative approaches, second opinion.
```

See [`examples/hello-agents/`](examples/hello-agents/) for the full walkthrough.

## Common Workflows

### Coordinator, Implementer, Reviewer

Use one pane as coordinator, one as implementer, and one as reviewer. Name panes
early so instructions stay readable:

```bash
tmux-agent name %1 coordinator
tmux-agent name %2 implementer
tmux-agent name %3 reviewer
tmux-agent send implementer "Implement the failing test fix. Report files changed and tests run."
tmux-agent send reviewer "Review the implementation after the implementer replies."
```

### Parallel Review

Ask two agents to inspect the same change from different angles, then reconcile
their replies in the coordinator pane:

```bash
tmux-agent task codex "Review this branch for regressions. Focus on tests and edge cases."
tmux-agent task gemini "Review this branch independently. Focus on design and simplification."
```

When the workers are bare CLIs that don't speak the protocol (Codex, Gemini,
DeepSeek, local models), use **pull mode** instead: delegate with `--await`, then
collect both replies in one blocking call — no worker needs to run `tmux-agent`,
and nothing is typed back into your pane.

```bash
tmux-agent task --await codex "Review this branch for regressions."
tmux-agent task --await gemini "Review this branch independently."
tmux-agent await codex gemini            # blocks until both finish, then prints both replies
```

### Large Handoffs

For diffs, logs, summaries, or review packets, prefer thread transport. The
receiver gets a compact ping and reads the payload only when needed:

```bash
tmux-agent send --path reviewer handoff.md
tmux-agent thread stat <thread-id>
tmux-agent thread read <thread-id> --head 80
```

Use `tmux-agent pause "reason"` to stop cross-pane sends during a runaway loop,
`tmux-agent status` to check the kill switch, and `tmux-agent audit tail` to
inspect recent sends during debugging.

## Mental model

| Role | Description |
|---|---|
| **Orchestrator** | Claude Code — the `/agent-mux` skill auto-loads there; it decomposes work, delegates, and integrates replies |
| **Workers** | Codex, Gemini, DeepSeek, local models — receive tasks and reply; they participate, they don't coordinate. Sandboxed workers may be pull-only — see [`orchestration.md`](skills/agent-mux/references/orchestration.md) |
| **tmux-agent** | The message bus — routes messages between panes |
| **Thread transport** | Large artifact channel — keeps diffs, logs, and file content out of prompt context |

agent-mux is Claude-centric: any pane/agent can participate, but only Claude
auto-loads the skill and drives orchestration. A worker can still be handed the
protocol manually (`tmux-agent task`, or feed it `SKILL.md`), but sustained
coordination is Claude's role.

### Coordination durability

agent-mux does not provide long-term memory or automatic RAG. The durable state is the installed skill plus explicit files in your project. When chats get long or an agent starts skipping coordination steps, reload the skill and follow its coordination contract:

- reply to `[tmux-agent v1 ... reply=<pane>]` messages with `tmux-agent send <pane> ...`
- use `tmux-agent task` for skill-unaware agents and `tmux-agent send` for normal handoffs
- for bare-CLI workers, prefer pull mode: `tmux-agent task --await <pane>` then collect with `tmux-agent await`
- include worker ownership, review, testing, and follow-up in multi-agent plans
- summarize delegated work before finalizing

Use your agent's native memory system for persistent project facts. Use `tmux-agent` thread transport for large handoffs and explicit session summaries between panes.

## Install

### Global tools (once per machine)

```bash
curl -fsSL https://maxto.github.io/agent-mux/install.sh | bash
```

Installs `tmux-agent` and `agent-mux` into `~/.agent-mux/bin/` and adds them to your PATH. Also installs tmux if missing, and installs the Claude Code skill **user-wide** at `~/.claude/skills/agent-mux/` so `/agent-mux` works in every folder without a per-project step. By default it installs the agent-mux tmux config, backs up any existing config, and symlinks it at `~/.config/tmux/tmux.conf`.

> The installer modifies your shell rc file (`~/.bashrc` or `~/.zshrc`) to add `~/.agent-mux/bin` to PATH, may install tmux or xclip via your package manager if they are missing, and may manage `~/.config/tmux/tmux.conf` unless you pass `--no-config`.

To keep your tmux config untouched during global install:

```bash
curl -fsSL https://maxto.github.io/agent-mux/install.sh | bash -s -- --no-config
```

### Per-project skill — only for non-Claude agents

Claude's `/agent-mux` is already global after the step above. Run this only when you want any non-Claude agent (Codex, Gemini, local models, …) in a specific repo to discover `tmux-agent`:

```bash
cd your-project
agent-mux install
```

Writes the neutral skill to `skills/agent-mux/` and ensures the tmux config is installed unless you pass `--no-config`. Without it, non-Claude agents in that repo don't know `tmux-agent` exists.

### tmux config

```bash
agent-mux install
```

Installs the agent-mux tmux config by default, backs up your existing one to `~/.agent-mux/backups/`, and symlinks it at `~/.config/tmux/tmux.conf`. Adds:

- **Mouse support** — click to select pane, drag to copy, scroll wheel enters scroll mode
- **Clipboard integration** — drag-to-copy writes to system clipboard (WSL, macOS, Linux)
- **Alt-key navigation** — move between panes and windows without a prefix key
- **Pane labels** — border shows pane name or current path
- **10,000 line scrollback**

To keep a personal tmux config untouched, opt out explicitly:

```bash
agent-mux install --no-config
# or
agent-mux install --config=false
```

## agent-mux CLI

| Command | Description |
|---|---|
| `agent-mux install` | Install the neutral skill into `$PWD` (for non-Claude agents) and install the tmux config by default. Claude's `/agent-mux` is already user-wide |
| `agent-mux install --no-config` | Install the neutral skill but leave the user's tmux config untouched |
| `agent-mux install --with-config` | Accepted for compatibility; config install is already the default |
| `agent-mux install --project-dir <path>` | Install the neutral skill into `<path>` instead of `$PWD` |
| `agent-mux update` | Re-download tmux-agent and agent-mux CLI; refresh the user-wide Claude skill; refresh tmux config only when `~/.config/tmux/tmux.conf` is managed by agent-mux; refresh the neutral skill if present in `$PWD` |
| `agent-mux session` | Show session help; does not create panes or attach |
| `agent-mux session start [--name agent] [--labels a,b,c] [--cmds x,y,z]` | Create a **new detached** session (default name `agent`, single pane). With `--labels`: one pane per label. Never splits the current window; errors if the name exists; does not attach |
| `agent-mux session list` | List tmux sessions |
| `agent-mux session kill --name <session>` | Kill a specific tmux session |
| `agent-mux window rename <name> [--target <window>]` | Rename the current tmux window; pass `--target` when outside tmux |
| `agent-mux attach [session]` | Attach or switch to an existing session; default: `agent` |
| `agent-mux open [session]` | Alias for `attach`; does not create sessions |
| `agent-mux uninstall` | Remove `~/.agent-mux/`, restore previous tmux config file or symlink from backup when available. Note: does not remove the `PATH` line added to your shell rc file. |
| `agent-mux keys` | Print the keyboard shortcuts for the agent-mux tmux config (alias: `agent-mux controls`) |
| `agent-mux version` | Print version |
| `agent-mux --help` | Show the agent-mux CLI reference, including the tmux-agent command summary |

### Files

| Path | Description |
|---|---|
| `~/.agent-mux/bin/tmux-agent` | Cross-pane communication CLI |
| `~/.agent-mux/bin/agent-mux` | agent-mux CLI |
| `~/.agent-mux/tmux.conf` | tmux config (downloaded by default) |
| `~/.agent-mux/backups/` | Config backups and previous symlink targets |
| `~/.claude/skills/agent-mux/` | Claude Code skill — `/agent-mux` in every folder (user-wide) |
| `skills/agent-mux/` | Per-project skill — neutral path for non-Claude agents |

## Controls

> Requires the agent-mux tmux config, installed by default. All shortcuts use **Alt** on Linux/Win-WSL2, **Option** on macOS — no prefix key. Run `agent-mux keys` to print this table from the terminal.

### Status Bar

The status bar keeps tmux context visible without command prompts:

```text
0:agents  1:logs  2:shell                    s: agmux, p: 3, 17:30:12
```

- Left: tmux window list, with the current window highlighted
- Right: current session (`s`), pane count in the active window (`p`), and live time
- The pane count updates when you switch windows; the clock updates every second
- Pane borders show `label: %target`, for example `codex: %0`


  | Type | Key | Action |
  |---|---|---|
  | Pane | `Alt+i` | Navigate up (no wrap) |
  | Pane | `Alt+k` | Navigate down (no wrap) |
  | Pane | `Alt+j` | Navigate left (no wrap) |
  | Pane | `Alt+l` | Navigate right (no wrap) |
  | Pane | `Alt+n` | New pane |
  | Pane | `Alt+w` | Close pane |
  | Pane | `Alt+o` | Cycle layouts |
  | Pane | `Alt+g` | Mark pane |
  | Pane | `Alt+y` | Swap with marked pane |
  | Window | `Alt+m` | New window |
  | Window | `Alt+u` | Next window |
  | Window | `Alt+h` | Previous window |
  | Scroll | `Alt+Tab` | Toggle scroll mode |
  | Scroll | `i` / `k` | Scroll up / down |
  | Scroll | `I` / `K` | Half-page up / down |
  | Scroll | `q` / `Esc` | Exit scroll mode |
  | Scroll | scroll wheel | Enter scroll mode automatically |

### Mouse

> The tmux mouse behavior requires the agent-mux tmux config, installed by default. Click, drag, and scroll work anywhere tmux mouse mode and clipboard integration are supported. Windows Terminal also provides the paste shortcuts below.

| Action | Result |
|---|---|
| Click | Select pane |
| Drag | Copy selected text to system clipboard |
| Scroll wheel | Enter scroll mode |

**Windows Terminal paste shortcuts:**

| Action | Result |
|---|---|
| `Shift+right-click` | Paste from Windows clipboard |
| `Ctrl+Shift+V` | Paste from Windows clipboard |

## tmux-agent

A CLI to send text to any tmux pane — without copy-paste. Works from your shell or from an AI agent.

The CLI is the source of truth — it documents itself rather than duplicating
docs here:

- `tmux-agent --help` — every command, the read guard, target resolution, env vars
- `tmux-agent protocol` — reply rules, the `[tmux-agent v1 ...]` header format, thread pings, trust model

### Targets

A target identifies a pane. Three formats work:

- **Label** — a name you set: `codex`, `worker`
- **Pane ID** — tmux native: `%3`
- **Full address** — `session:window.pane`: `agents:0.1`

Name a pane once, use the label everywhere; for a receiver that may not know
agent-mux yet, use `task` (it appends reply/protocol instructions):

```bash
tmux-agent name %1 codex
tmux-agent send codex "hello"
tmux-agent task codex "Review the installer changes. Reply with risks and tests."
```

The read guard (you must `read` a pane before `type`/`keys`) and the message
header convention are documented in `tmux-agent --help` and `tmux-agent protocol`.

### Pull mode (`task --await` + `await`)

Push delivery (`send`/`task` + reply) needs the worker to run `tmux-agent` to
answer, and to do so while your pane is idle. Bare-CLI workers (Codex, Gemini,
DeepSeek, local models) often can't, and a reply typed back while you're busy can
race your turn. Pull mode removes both problems: **the worker just prints its
answer; you pull it when you're ready.**

```bash
tmux-agent task --await codex "Audit scripts/tmux-agent and list risks."
tmux-agent task --await %5    "Check install.sh OS detection."
tmux-agent await codex %5 --timeout 600
```

- `task --await` appends a footer asking the worker to wrap its answer between two
  marker lines (`<<<label@%N reply NONCE>>>` … `<<<…done NONCE>>>`) and records
  the expected marker in a state file. The worker needs no protocol knowledge.
- `await <target>...` blocks until **every** target prints its done marker or hits
  the timeout (default 300s, `--timeout N` or `TMUX_AGENT_AWAIT_TIMEOUT`), then
  prints one delimited block per target — only the answers, so a fan-out collapses
  to a single ingestion. Nothing is injected into your pane.
- A timed-out target shows `=== TIMEOUT … ===` with its last pane lines; the rest
  still return their answers.

Pull mode coexists with push — keep `send`/`task` + reply for agents that already
speak the protocol (e.g. another Claude).

### Thread transport (large payloads)

For payloads over 2KB, `send` automatically switches to file-based transport. The pane receives only a compact ping; the message lives on the filesystem. Prompt growth stays flat regardless of payload size until the receiver explicitly reads the thread.

```bash
# Let send auto-promote above 2KB, or force file transport with --path (reads file directly)
tmux-agent send --path codex large-diff.txt
# → thread: 20260424T101530Z-1a2b3c4d
```

The receiver's pane gets a compact ping:
```
[tmux-agent v1 kind=thread thread=20260424T101530Z-1a2b3c4d seq=000001 from=claude pane=%4 reply=%4]
```

At this point, the receiver can choose:

- reply immediately without loading the large payload into prompt context yet
- defer the read until they actually need the content
- read the thread now if the task requires full inspection

The receiver reads the thread only when needed:
```bash
tmux-agent thread list --limit 10
tmux-agent thread stat 20260424T101530Z-1a2b3c4d
tmux-agent thread read 20260424T101530Z-1a2b3c4d --head 80
tmux-agent thread read 20260424T101530Z-1a2b3c4d --since-cursor
```

Then replies with `send` or `send --file` to the `reply=` pane from the ping header.

Threads are stored in `${XDG_RUNTIME_DIR:-/tmp/agent-mux-<uid>}/threads/`
or `TMUX_AGENT_THREAD_DIR` when set. List them with `thread list` and clean
them up with `thread gc`; use `thread gc --dry-run` first to preview removals.

**Why this matters:** with inline transport, the full payload enters the receiver's prompt immediately. With thread transport, only the ping enters the prompt by default; the large body stays on disk until `thread read`.

Example:

- Inline: send a 12KB diff directly -> the receiver pays the full 12KB in prompt context right away
- Thread transport: send the same 12KB diff with `send --file` -> the receiver sees only the ping and can answer "received" without loading the diff yet

In a live benchmark with the same 12KB payload:

- inline prompt growth: `12288` chars
- thread ping prompt growth: `114` chars

That's about `99%` less prompt growth per handoff before the receiver reads the thread.

For a repeatable benchmark protocol, see [examples/live-thread-benchmark/README.md](examples/live-thread-benchmark/README.md).

### Security model

`tmux-agent` is a coordination layer for trusted participants in the same tmux session — not an authenticated channel. Any process with access to the tmux socket can read panes and write input. The `msg` ID is for demultiplexing, not authentication. Use the pane ID (`pane=`) as the primary identity when routing replies, not the label (`from=`).

### Examples

**Step 1 — see what's open:**
```bash
tmux-agent list
```

**Step 2 — name your panes:**
```bash
tmux-agent name %1 codex
tmux-agent name %2 worker
```

**Send a message to another pane:**
```bash
tmux-agent send codex "please review src/auth.ts"
```

**Read what's in a pane:**
```bash
tmux-agent read worker        # last 50 lines
tmux-agent read worker 10     # last 10 lines
```

**Approve a yes/no prompt in another pane:**
```bash
tmux-agent read worker        # see the prompt
tmux-agent type worker "y"
tmux-agent read worker        # verify "y" appeared
tmux-agent keys worker Enter
```

## Window Names

Use `agent-mux window rename` for normal window naming instead of raw tmux:

```bash
agent-mux window rename work
agent-mux window rename logs --target agents:0
```

The left side of the status bar shows tmux windows as `<index>:<name>`, so
renaming the current window changes `0:agents` to something like `0:work`.

### Environment

| Variable | Description |
|---|---|
| `TMUX_AGENT_SOCKET` | Override the tmux server socket path (skips auto-detection) |
| `TMUX_AGENT_THREAD_DIR` | Override thread storage path (default: `${XDG_RUNTIME_DIR:-/tmp/agent-mux-<uid>}/threads`). Useful for persistent, shared, or sandbox-specific thread stores. |
| `TMUX_AGENT_CURSOR_DIR` | Override cursor storage path (default: `/tmp/agent-mux-<uid>/cursors`). Set this in sandboxed environments where `XDG_RUNTIME_DIR` is read-only. |
| `TMUX_AGENT_INLINE_THRESHOLD` | Max bytes for inline `send` before auto-spill to file transport (default: `2048`; `0` = always use file transport) |
| `TMUX_AGENT_AWAIT_TIMEOUT` | Seconds `await` waits per target before timing out (default: `300`) |

### Useful low-level tmux commands

Prefer `agent-mux session start`, `agent-mux attach`, and `agent-mux open` for
agent-mux-managed sessions. Use raw tmux commands only when you intentionally
need tmux behavior outside the agent-mux workflow.

| Command | Description |
|---|---|
| `tmux new-session -s agents` | Create a raw tmux session named `agents` |
| `tmux attach -t agents` | Reattach to raw tmux session `agents` |
| `tmux list-sessions` | List all active sessions |
| `tmux kill-session -t agents` | Kill session `agents` |

See the [agent-mux skill](skills/agent-mux/SKILL.md) for full documentation on agent-to-agent workflows.

### Role Frameworks

agent-mux does not hardcode roles. Claude (the orchestrator) assigns them per
task, gives each worker explicit ownership, forbidden files, and expected
output, and keeps QA/Security/Adversarial workers read-only by default. Role
frameworks and ownership templates live in
[`references/orchestration.md`](skills/agent-mux/references/orchestration.md).

## AI Agent Skills

A **skill** is a markdown file loaded into an agent's context that explains how to use a tool — in this case, how to use `tmux-agent` to read panes, send messages, and coordinate with other agents. The top-level skill is intentionally short and points agents to specific references only when needed.

The skill lives in two places:

- **`~/.claude/skills/agent-mux/`** — user-wide, installed by `curl | bash`. Makes `/agent-mux` available to Claude Code in **every** folder, no per-project step.
- **`skills/agent-mux/`** — per-project neutral path, written by `agent-mux install`, readable by non-Claude agents in that repo.

agent-mux is Claude-centric: in **Claude Code** the skill auto-loads with
`/agent-mux` anywhere, and Claude orchestrates. Worker agents do not need the full skill
— `tmux-agent task` appends everything they need to reply. If you do want a
worker to know the protocol, point it at `skills/agent-mux/SKILL.md` (paste it
into the system prompt or use the agent's file-loading command). agent-mux does
not install Claude, Codex, Gemini, or any model-specific CLI.


## Requirements

- **OS**: Linux, macOS, or Windows (WSL2)
- **tmux**: 3.2+ — installed automatically if missing (macOS requires [Homebrew](https://brew.sh))
- **Shell**: bash
- **For install / update**: curl or wget
