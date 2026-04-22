# agent-mux

tmux for humans and multi-model AI teams. Works on Linux, macOS, and WSL2 (Windows Terminal).

- **For humans** — tmux without the learning curve: Alt-key navigation, mouse support, and labeled panes. No prefix key, no config expertise required.
- **For agents** — `tmux-agent` gives any CLI agent (Claude Code, Codex, aider, Gemini CLI, local models via Ollama, OpenDevin, or any bash-capable tool) a unified way to read, write, and communicate across panes.
- **Multi-model workflows** — run multiple agents in parallel on the same codebase. Collaborative builds, adversarial review, cross-model verification — coordinated through tmux panes.

## Quickstart

```bash
# 1. Install once per machine
curl -fsSL https://maxto.github.io/agent-mux/install.sh | bash

# 2. Install the /agent-mux skill into your project (once per project)
cd your-project
agent-mux install

# 3. In Claude Code, load the skill
/agent-mux
```

Your coordinator agent now knows how to use `tmux-agent` to talk to other panes, launch agents, and coordinate work.

> **Note:** the first `curl` installs global tools and also copies the skill into whatever directory you're in. Run it from `~` if you don't want the skill installed there, then `cd your-project && agent-mux install`.

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

Copies the `/agent-mux` skill into `.claude/skills/agent-mux/`. This teaches AI agents (Claude Code, Codex, Gemini CLI, etc.) how to use `tmux-agent` — without it, they don't know the tool exists. In Claude Code, invoke it with `/agent-mux`.

> `agent-mux install` also re-downloads the global binaries (`tmux-agent`, `agent-mux`) — it is safe to run multiple times. If you already ran the `curl` command in your project directory, running `agent-mux install` again is still safe but the skill will simply be refreshed.

### tmux config (optional)

```bash
agent-mux install --with-config
```

Installs the agent-mux tmux config: Alt-key navigation, mouse clipboard, labeled panes. Your existing config is backed up to `~/.agent-mux/backups/` and a symlink is created at `~/.config/tmux/tmux.conf`. Required for the keybindings described in this README.

## agent-mux CLI

| Command | Description |
|---|---|
| `agent-mux install` | Install tmux-agent, agent-mux CLI, and the `/agent-mux` skill into `$PWD` |
| `agent-mux install --with-config` | Also install the tmux config, symlinked to `~/.config/tmux/tmux.conf` (existing config backed up to `~/.agent-mux/backups/`) |
| `agent-mux install --project-dir <path>` | Install the `/agent-mux` skill into `<path>/.claude/skills/agent-mux/` instead of `$PWD` |
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
| `.claude/skills/agent-mux/` | Claude Code `/agent-mux` skill (installed to project dir) |

## Keybindings

> These keybindings require the agent-mux tmux config. Install it with `agent-mux install --with-config`.

All keybindings use **Alt** on Linux and WSL2 / **Option** on macOS — no prefix required.

### Panes

| Key | Action |
|---|---|
| `Alt+i` | Navigate up (no wrap) |
| `Alt+k` | Navigate down (no wrap) |
| `Alt+j` | Navigate left (no wrap) |
| `Alt+l` | Navigate right (no wrap) |
| `Alt+n` | New pane (horizontal split + auto-tile) |
| `Alt+w` | Close pane |
| `Alt+o` | Cycle layouts |
| `Alt+g` | Mark pane |
| `Alt+y` | Swap with marked pane |

### Windows

| Key | Action |
|---|---|
| `Alt+m` | New window |
| `Alt+u` | Next window (no wrap) |
| `Alt+h` | Previous window (no wrap) |

### Scroll mode

| Key | Action |
|---|---|
| `Alt+Tab` | Toggle scroll mode |
| `i` / `k` | Scroll up / down (2 lines) |
| `I` / `K` | Half-page up / down |
| `q` or `Escape` | Exit scroll mode |

Scroll wheel also enters scroll mode automatically.

### Mouse

> Requires `agent-mux install --with-config`.

- Click to select panes
- Drag to select text — auto-copies to clipboard (clip.exe on WSL2, pbcopy on macOS, xclip/xsel on Linux)
- Right-click — paste from Windows clipboard (WSL2, Windows Terminal native)
- Shift+right-click — paste via context menu (verified paste)
- Scroll wheel enters scroll mode

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

agent-mux works with any agent that can run bash. How each agent loads the skill:

| Agent | How to load the skill |
|---|---|
| Claude Code | `/agent-mux` (after `agent-mux install` in your project) |
| Codex | `/init` — reads `.claude/skills/agent-mux/SKILL.md` automatically |
| Gemini CLI | `@.claude/skills/agent-mux/SKILL.md` or include in context |
| aider | `/add .claude/skills/agent-mux/SKILL.md` |
| Ollama / local models | Paste or include `SKILL.md` in your system prompt |
| Other agents | Any agent that can read a file or accept a system prompt works |

For agents that support skills.sh, install via:

```bash
npx skills add maxto/agent-mux
```

Works with Claude Code, Codex, Cursor, Copilot, and [45+ other agents](https://github.com/vercel-labs/skills#supported-agents).


## Requirements

- Linux, WSL2 (Windows Subsystem for Linux), or macOS (requires [Homebrew](https://brew.sh))
- tmux 3.2+ — installed automatically by `agent-mux install` if missing
- bash
- curl or wget (for install)
