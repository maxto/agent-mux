# agent-mux

agent-mux is tmux for people and AI agents working in the same terminal.

- **Humans get a friendlier tmux**: Alt-key navigation, mouse support, labeled panes, and no prefix-key muscle memory required.
- **Agents get a shared control layer**: `tmux-agent` lets Claude Code, Codex, Gemini CLI, aider, local models, and other bash-capable agents read panes, send input, and reply across panes.
- **Teams get parallel model workflows**: run multiple agents on the same repo for implementation, review, testing, and cross-checking without leaving tmux.

## Quickstart

```bash
# 1. Install global tools — once per machine
curl -fsSL https://maxto.github.io/agent-mux/install.sh | bash

# 2. Install the skill — once per project
cd your-project
agent-mux install

# 3. In Claude Code, load the skill
/agent-mux
```

Your coordinator agent now knows how to use `tmux-agent` to talk to other panes, launch agents, and coordinate work.

## Example

Three agents, one project. One coordinator agent handles everything else.

> "Set up a 3-agent session with Codex and Gemini. Ask each one their role."

The coordinator sets up the panes, launches the agents, and coordinates via `tmux-agent`:

```
[from:codex] Ready. Code review, implementation, bug analysis.
[from:gemini] Ready. Adversarial review, alternative approaches, second opinion.
```

See [`examples/hello-agents/`](examples/hello-agents/) for the full walkthrough.

## Install

### Global tools (once per machine)

```bash
curl -fsSL https://maxto.github.io/agent-mux/install.sh | bash
```

Installs `tmux-agent` and `agent-mux` into `~/.agent-mux/bin/` and adds them to your PATH. Also installs tmux if missing. Your existing tmux config is **not touched**.

> The installer modifies your shell rc file (`~/.bashrc` or `~/.zshrc`) to add `~/.agent-mux/bin` to PATH, and may install tmux or xclip via your package manager if they are missing.

### Per-project skill (once per project)

```bash
cd your-project
agent-mux install
```

Installs the skill into two paths: `skills/agent-mux/` (neutral, any agent) and `.claude/skills/agent-mux/` (Claude Code `/agent-mux` slash command). This teaches any AI agent how to use `tmux-agent` — without it, they don't know the tool exists.

### tmux config (optional)

```bash
agent-mux install --with-config
```

Installs the agent-mux tmux config: Alt-key navigation, mouse clipboard, labeled panes. Your existing config is backed up to `~/.agent-mux/backups/` and a symlink is created at `~/.config/tmux/tmux.conf`. Required for the keybindings described in this README.

## agent-mux CLI

| Command | Description |
|---|---|
| `agent-mux install` | Install the `/agent-mux` skill into `$PWD` (neutral + Claude Code paths) |
| `agent-mux install --with-config` | Also install the tmux config, symlinked to `~/.config/tmux/tmux.conf` (existing config backed up to `~/.agent-mux/backups/`) |
| `agent-mux install --project-dir <path>` | Install the skill into `<path>` instead of `$PWD` |
| `agent-mux update` | Re-download tmux-agent and agent-mux CLI; refreshes tmux config only if `--with-config` was previously used; refreshes skill if present in `$PWD` |
| `agent-mux uninstall` | Remove `~/.agent-mux/`, restore previous tmux config from backup (if available). Note: does not remove the `PATH` line added to your shell rc file. |
| `agent-mux version` | Print version |
| `agent-mux help` | Show tmux-agent and keybinding cheatsheet |

### Files

| Path | Description |
|---|---|
| `~/.agent-mux/bin/tmux-agent` | Cross-pane communication CLI |
| `~/.agent-mux/bin/agent-mux` | agent-mux CLI |
| `~/.agent-mux/tmux.conf` | tmux config (downloaded by `--with-config`) |
| `~/.agent-mux/backups/` | Config backups (created by `--with-config`) |
| `skills/agent-mux/` | Skill — neutral path (Codex, Gemini, aider, any agent) |
| `.claude/skills/agent-mux/` | Skill — Claude Code `/agent-mux` slash command |

## Controls

> Requires `agent-mux install --with-config`. All shortcuts use **Alt** on Linux/Win-WSL2, **Option** on macOS — no prefix key.


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

> Requires `agent-mux install --with-config`. Verified on Windows 11 + Win-WSL2 + Windows Terminal.

| Action | Result |
|---|---|
| Click | Select pane |
| Drag | Copy selected text to Windows clipboard |
| Scroll wheel | Enter scroll mode |
| `Shift+right-click` | Paste from Windows clipboard |
| `Ctrl+Shift+V` | Paste from Windows clipboard |

## tmux-agent

A CLI for cross-pane communication. Any tool that can run bash can use it — Claude Code, Codex, Gemini CLI, or a plain shell script.

```
claude  ──send──▶  tmux-agent  ──▶  codex pane
codex   ──send──▶  tmux-agent  ──▶  claude pane
```

### Reliability: the read guard

`tmux-agent` enforces a read-before-act protocol: an agent must call `read` before `type` or `keys`. This prevents agents from typing into stale or unexpected pane state — a common failure mode in unguarded tmux automation. `send` handles the full cycle automatically.

### Command reference

| Command | Description | Example |
|---|---|---|
| `tmux-agent list` | Show all panes with target, session:window, size, process, label, CWD | `tmux-agent list` |
| `tmux-agent read <target> [lines]` | Read last N lines from a pane (default: 50) | `tmux-agent read codex 20` |
| `tmux-agent type <target> <text>` | Type text into a pane without pressing Enter | `tmux-agent type claude "review src/auth.ts"` |
| `tmux-agent keys <target> <key>...` | Send special keys | `tmux-agent keys codex Enter` |
| `tmux-agent send <target> <text>` | Read → message → verify → Enter in one step | `tmux-agent send codex "what is 2+2"` |
| `tmux-agent name <target> <label>` | Label a pane for easy addressing | `tmux-agent name %1 claude` |
| `tmux-agent resolve <label>` | Look up a pane target by label | `tmux-agent resolve claude` → `%1` |
| `tmux-agent id` | Print this pane's ID | `tmux-agent id` → `%3` |
| `tmux-agent message <target> <text>` | Type text with auto-prepended sender info (no Enter) | `tmux-agent message codex "ping from claude"` |
| `tmux-agent doctor` | Diagnose tmux connectivity issues | `tmux-agent doctor` |
| `tmux-agent version` | Print version | `tmux-agent version` |

### Target resolution

Targets can be tmux native (`session:window.pane`, `%N`) or a label set via `name`. Labels are resolved automatically:

```bash
tmux-agent name %1 claude
tmux-agent name %2 codex
tmux-agent send codex "ping from claude"
```

### Environment

| Variable | Description |
|---|---|
| `TMUX_AGENT_SOCKET` | Override the tmux server socket path (skips auto-detection) |

### Useful tmux commands

| Command | Description | Example |
|---|---|---|
| `tmux attach -t <session>` | Reattach to an existing session | `tmux attach -t agents` |
| `tmux switch-client -t <session>` | Switch to a session from inside tmux | `tmux switch-client -t agents` |
| `tmux list-sessions` | List all active sessions | `tmux list-sessions` |
| `tmux new-session -s <name>` | Create a new named session | `tmux new-session -s agents` |
| `tmux kill-session -t <name>` | Kill a session | `tmux kill-session -t agents` |

See the [agent-mux skill](skills/agent-mux/SKILL.md) for full documentation on agent-to-agent workflows.

## AI Agent Skills

A **skill** is a markdown file loaded into an agent's context that explains how to use a tool — in this case, how to use `tmux-agent` to read panes, send messages, and coordinate with other agents.

`agent-mux install` automatically copies the skill into `.claude/skills/agent-mux/` in your current project. In Claude Code, invoke it with `/agent-mux` to load the full tmux-agent documentation into context.

agent-mux works with any agent that can run bash. `agent-mux install` copies the skill to two paths:

- **`skills/agent-mux/`** — neutral path, readable by any agent
- **`.claude/skills/agent-mux/`** — Claude Code slash command support

How each agent loads the skill:

| Agent | How to load the skill |
|---|---|
| Claude Code | `/agent-mux` slash command |
| Codex | `/init` — reads `skills/agent-mux/SKILL.md` automatically |
| Gemini CLI | `@skills/agent-mux/SKILL.md` |
| aider | `/add skills/agent-mux/SKILL.md` |
| Ollama / local models | Paste or include `skills/agent-mux/SKILL.md` in system prompt |
| Other agents | Any agent that can read a file or accept a system prompt works |

For agents that support skills.sh, install via:

```bash
npx skills add maxto/agent-mux
```

Works with Claude Code, Codex, Cursor, Copilot, and [45+ other agents](https://github.com/vercel-labs/skills#supported-agents).


## Requirements

- Linux, Win-WSL2 (Windows Subsystem for Linux), or macOS (requires [Homebrew](https://brew.sh))
- tmux 3.2+ — installed automatically by `agent-mux install` if missing
- bash
- curl or wget (for install)
