# Repository Guidelines

## Project Structure & Module Organization

This repository is a pure Bash project for `agent-mux`, a tmux setup and cross-pane communication tool. Core implementation lives in `install.sh` for the `agent-mux` CLI/installer and `scripts/tmux-agent` for tmux pane messaging. The tmux configuration is `.tmux.conf`; user-facing help text is `help.txt`. Agent integration docs live under `skills/agent-mux/`, with supporting references in `skills/agent-mux/references/`. Tests are split into `tests/install/` for installer behavior and `tests/tmux-agent/` for CLI behavior; shared command mocks are in `tests/fixtures/bin/`. Examples belong in `examples/`.

## Build, Test, and Development Commands

There is no build step or package manager. Run scripts directly:

```bash
bash install.sh                         # local installer smoke test
bash -n install.sh scripts/tmux-agent   # syntax check
shellcheck install.sh scripts/tmux-agent
bats tests/install/
bats tests/tmux-agent/
```

The GitHub Actions workflow runs ShellCheck first, then Bats tests. Some `tests/tmux-agent/` cases require a real `tmux` binary.

## Coding Style & Naming Conventions

Use Bash with `set -euo pipefail` for executable scripts. Keep functions small, named in `snake_case`, and prefer `local` variables inside functions. Use uppercase names for constants and environment variables, for example `VERSION`, `TMUX_AGENT_SOCKET`, and `TMUX_AGENT_INLINE_THRESHOLD`. Quote variable expansions unless Bash pattern or array behavior is intentional. Add ShellCheck suppressions only with a short reason.

## Testing Guidelines

Write tests in Bats and name files by behavior area, such as `read_guard.bats` or `send_threshold.bats`. Test names should describe observable behavior: `@test "send: threshold=0 forces file transport"`. Installer tests should isolate `HOME` and use fixtures from `tests/fixtures/bin/`; tmux-agent integration tests should create and clean up their own tmux socket and temporary runtime directories.

## Commit & Pull Request Guidelines

History uses Conventional Commit-style prefixes such as `feat:`, `fix:`, `docs:`, and `chore:`. Keep commits focused and imperative, for example `fix: preserve trailing newlines in send --path`. Pull requests should explain the behavior change, list the tests run, link related issues when applicable, and include screenshots or terminal snippets only for user-visible CLI or tmux changes.

## Agent-Specific Instructions

Do not weaken `tmux-agent` read-before-act behavior: agents must read a pane before typing or sending keys. Keep installer changes conservative because `install.sh` modifies user shell rc files and may manage `~/.config/tmux/tmux.conf` only when `--with-config` is requested.
