# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Memory

Project memory lives in `.claude/memory/` (gitignored). Read `MEMORY.md` there for context at the start of each session.

## What This Is

**agent-mux** is a one-command tmux setup with a cross-pane CLI (`tmux-agent`) designed for AI agent terminal automation. Four deliverables:

1. `.tmux.conf` — opinionated tmux config with Option-key bindings
2. `scripts/tmux-agent` — bash CLI for reading/writing across tmux panes
3. `install.sh` — curl-installable setup script
4. `skills/agent-mux/SKILL.md` — agent integration documentation (installed to both `skills/` and `.claude/skills/`)

agent-mux is not a memory system, RAG layer, or codebase knowledge graph. Keep
the core focused on tmux workspace management, cross-pane protocol, and concise
agent instructions.

## Installation & Update

```bash
# Install from hosted URL
curl -fsSL https://maxto.github.io/agent-mux/install.sh | bash

# Keep a personal tmux config untouched
agent-mux install --no-config

# After cloning locally, run install directly
bash install.sh

# Update all components
agent-mux update

# Remove
agent-mux uninstall
```

No build step. No package manager. Pure bash — `install.sh` downloads binaries to `~/.agent-mux/`. The default install manages the agent-mux tmux config and backs up existing config; `--no-config` opts out.

For normal user workflows, prefer `agent-mux` commands over raw `tmux` when a
high-level command exists. For example, use `agent-mux window rename <name>` to
rename the current window, or `agent-mux window rename <name> --target
<session:window>` when outside tmux. Raw `tmux rename-window` is only a
low-level fallback.

## Testing

Run automated checks before committing:

```bash
bash -n install.sh scripts/tmux-agent
shellcheck install.sh scripts/tmux-agent
bats tests/install/
bats tests/tmux-agent/
```

Manual smoke checks when needed:

```bash
tmux-agent doctor
tmux-agent protocol
tmux-agent list
tmux-agent task <pane-target> "task with reply instructions"
tmux-agent read <pane-target>
tmux-agent type <pane-target> "text"
tmux-agent keys <pane-target> Enter
```

## Release Rule

Read the current version from `VERSION` in `install.sh` and `scripts/tmux-agent`.
Whenever those versions change, create and push the exact matching tag after
pushing `main`, for example `v1.9.4`. This applies to patch, minor, and major
releases. `install.sh` downloads release files from `v${VERSION}`, so a missing
tag breaks fresh installs. Docs-only or test-only commits without a version bump
do not need a tag.

## Architecture

### tmux-agent read-guard

The core safety mechanism: an agent must call `read` before `type` or `keys`. A `/tmp/tmux-agent-read-<pane-id>` marker file is created on read and consumed on type/keys. Bypassing this is intentional — don't weaken it.

### Target resolution

Pane targets accept: tmux natives (`%3`, `session:window.pane`, window index `0`), or custom labels set via `tmux-agent name <target> <label>`. Labels are stored in the `@name` pane option and resolved at runtime.

### Message convention

`tmux-agent message` auto-prepends a header:
```
[tmux-agent v1 from=<sender> pane=<pane-id> at=<session:window.pane> msg=<id> reply=<pane-id>]
```
This lets recipient agents reply directly using the `reply=` pane ID. Agents must **not** poll or wait after sending — the recipient replies into the sender's pane. Use `tmux-agent task` when the receiver may not know this protocol yet.

### Socket detection order

1. `TMUX_AGENT_SOCKET` env var
2. `$TMUX` env (current session's socket)
3. Scan all panes across running tmux servers
4. Fallback to default socket

Handles macOS `/tmp` → `/private/tmp` symlink transparently.

### install.sh flow

Detects OS/package manager → installs tmux if missing → downloads `tmux-agent` and `agent-mux` CLI → manages the agent-mux tmux config by default → adds `~/.agent-mux/bin` to shell rc. Config install backs up existing config to `~/.agent-mux/backups/`, downloads `.tmux.conf`, symlinks it to `~/.config/tmux/tmux.conf`, and reloads tmux if running. `--no-config` skips tmux config management.

## Editing Guidelines

- Touch only what the task requires. Don't improve adjacent code, comments, or formatting.
- When your changes make something unused (import, variable, function), remove it. Don't remove pre-existing dead code — mention it instead.
- No features, abstractions, or error handling beyond what was asked. If a simpler approach exists, say so before implementing.

## Key Design Constraints

- `type` uses tmux's `-l` (literal) flag — no shell expansion of `$`, quotes, etc.
- `type` intentionally omits Enter — forces explicit read-verify-enter pattern.
- No compound commands by design — keeps agent interactions debuggable.
- `agent-mux update` re-downloads from the hosted URL, not from local files — changes must be pushed to the remote to take effect via update.
- Use SSH remote for git push from inside tmux (`git@github.com:maxto/agent-mux.git`) — the VSCode credential helper is not accessible from tmux panes.
