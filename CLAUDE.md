# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Memory

Project memory lives in `.claude/memory/` (gitignored). Read `MEMORY.md` there for context at the start of each session.

## What This Is

**agent-mux** is a one-command tmux setup with a cross-pane CLI (`tmux-agent`) designed for AI agent terminal automation. Three deliverables:

1. `.tmux.conf` — opinionated tmux config with Option-key bindings
2. `scripts/tmux-agent` — bash CLI for reading/writing across tmux panes
3. `install.sh` — curl-installable setup script
4. `skills/agent-mux/SKILL.md` — agent integration documentation

## Installation & Update

```bash
# Install from hosted URL (safe — does not touch existing tmux config)
curl -fsSL https://maxto.github.io/agent-mux/install.sh | bash

# Also install the agent-mux tmux config (symlinks ~/.config/tmux/tmux.conf, backs up existing)
agent-mux install --with-config

# After cloning locally, run install directly
bash install.sh

# Update all components
agent-mux update

# Remove
agent-mux uninstall
```

No build step. No package manager. Pure bash — `install.sh` downloads binaries to `~/.agent-mux/`. The default install does **not** touch the user's tmux config; `--with-config` opts in to symlink management.

## Testing

No automated test suite. Manual verification:

```bash
# Check tmux-agent connectivity
tmux-agent doctor

# Exercise core commands
tmux-agent list
tmux-agent read <pane-target>
tmux-agent type <pane-target> "text"
tmux-agent keys <pane-target> Enter
```

## Architecture

### tmux-agent read-guard

The core safety mechanism: an agent must call `read` before `type` or `keys`. A `/tmp/tmux-agent-read-<pane-id>` marker file is created on read and consumed on type/keys. Bypassing this is intentional — don't weaken it.

### Target resolution

Pane targets accept: tmux natives (`%3`, `session:window.pane`, window index `0`), or custom labels set via `tmux-agent name <target> <label>`. Labels are stored in the `@name` pane option and resolved at runtime.

### Message convention

`tmux-agent message` auto-prepends a header:
```
[tmux-agent from:<sender> pane:<pane-id> at:<session:window.pane> - load the agent-mux skill to reply]
```
This lets recipient agents reply directly by pane ID. Agents must **not** poll or wait after sending — the recipient replies into the sender's pane.

### Socket detection order

1. `TMUX_AGENT_SOCKET` env var
2. `$TMUX` env (current session's socket)
3. Scan all panes across running tmux servers
4. Fallback to default socket

Handles macOS `/tmp` → `/private/tmp` symlink transparently.

### install.sh flow

Detects OS/package manager → installs tmux if missing → downloads `tmux-agent` and `agent-mux` CLI → adds `~/.agent-mux/bin` to shell rc. With `--with-config`: additionally backs up existing config to `~/.agent-mux/backups/`, downloads `.tmux.conf`, symlinks it to `~/.config/tmux/tmux.conf`, and reloads tmux if running.

## Key Design Constraints

- `type` uses tmux's `-l` (literal) flag — no shell expansion of `$`, quotes, etc.
- `type` intentionally omits Enter — forces explicit read-verify-enter pattern.
- No compound commands by design — keeps agent interactions debuggable.
- `agent-mux update` re-downloads from the hosted URL, not from local files — changes must be pushed to the remote to take effect via update.
- Use SSH remote for git push from inside tmux (`git@github.com:maxto/agent-mux.git`) — the VSCode credential helper is not accessible from tmux panes.
