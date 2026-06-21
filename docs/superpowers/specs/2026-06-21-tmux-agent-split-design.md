# Design: `tmux-agent split` — sanctioned pane creation in a live session

**Date:** 2026-06-21
**Status:** Approved (pending spec review)
**Version target:** 1.13.1 → 1.14.0 (minor)

## Problem

agent-mux exists to orchestrate multiple panes in the same session as a
tmux wrapper dedicated to agent communication. Yet a session's pane
composition is frozen at birth: `agent-mux session start --labels a,b,c`
splits and labels panes only when creating a *new detached* session
(`scripts/tmux-agent` has no `split` at all; `agent-mux` uses
`split-window` only internally at session start). After a session is
running, there is **no sanctioned command to add a pane**.

The only way to add a worker pane next to a running agent is to drop to
raw `tmux split-window`, then `tmux-agent name` to pull it into the
coordination layer. This was done in practice:

```bash
NEW=$(tmux split-window -h -t crm:0 -P -F '#{pane_id}' -c /home/maxto/macroasset/crm)
tmux-agent name "$NEW" pi
```

Dropping to raw tmux contradicts the product's reason to exist. CLAUDE.md
asks to prefer agent-mux commands *when a high-level command exists* and
treats raw tmux as a fallback — so this was not a rule violation, but it
is the signal that the command is missing.

## Goal

Add a first-class, agent-facing command that creates a pane in a live
window and returns its pane-id, so the full delegation chain stays inside
the CLI and never touches raw tmux.

## Non-goals (YAGNI)

- **No auto-labeling.** Labeling stays `tmux-agent name`.
- **No process launch.** Starting the worker (an agent, a python script,
  …) stays the existing `read` → `type` → `keys Enter` flow.
- **No change to `session start`.** It keeps "never splits the current
  window" — that is about creating *new* sessions and is a different
  concern. No conflict.

One command, one responsibility.

## Command surface

```
tmux-agent split [--cwd <dir>] [-h|-v] [--target <window>]
```

- **Defaults:** horizontal split (`-h`, worker *beside* the caller), in the
  **current window**, cwd = current pane's directory.
- `--cwd <dir>` — working directory of the new pane. (Only settable at
  creation in tmux; cannot be deferred to a later command.)
- `-h` / `-v` — split direction (horizontal / vertical). If both are
  passed, the last one wins.
- `--target <window>` — split a different window (e.g. `crm:0`), resolved
  via `resolve_target`. Required when running outside tmux.
- **Output:** prints **only the pane-id** to stdout (e.g. `%1`), so
  `NEW=$(tmux-agent split)` works. No other noise, mirroring `cmd_id`.

### Delegation chain it enables

```bash
NEW=$(tmux-agent split)            # create pane, returns %id
tmux-agent name "$NEW" pi          # label
tmux-agent read "$NEW"             # read-guard
tmux-agent type "$NEW" "python worker.py"
tmux-agent keys "$NEW" Enter       # launch
```

## Internal behavior (`cmd_split`)

Reuses existing patterns (~15 lines):

1. `require_tmux`
2. Parse flags with a `while/case` loop (clone of `cmd_list`'s parser).
3. Resolve where to split: with `--target`, `resolve_target` +
   `validate_target`; otherwise the current pane (`$TMUX_PANE`).
4. `tmx split-window <-h|-v> -t <target> [-c <dir>] -PF '#{pane_id}'`,
   capturing the new pane-id.
5. `echo` the captured pane-id.

### Read-guard invariant

`split` *creates* a pane; it does not type into an existing one, so it
neither consumes nor requires a read-guard marker. The new pane is born
without a marker, so writing into it still requires the agent to
`read` → `type` → `keys`. The core safety invariant is untouched.

## Error handling

- Outside tmux without `--target` → clear error and non-zero exit
  (same pattern as `name` / `list --current`).
- Non-existent `--cwd` → propagate the underlying `tmux split-window`
  error; do not reinvent the check.
- Non-existent `--target` → fails in `validate_target`.

## Dispatch & documentation changes

- Register `split` in the command allow-list (`scripts/tmux-agent`,
  dispatch around line 1537) and in the `case` dispatch (around line 1546).
- Add the `split` usage line to `tmux-agent`'s `usage` and to
  `agent-mux`'s `cmd_cli_ref` (the `tmux-agent — cross-pane communication`
  block).
- **SKILL.md** (`skills/agent-mux/SKILL.md`): correct the line
  *"tmux-agent does not create sessions or split panes"* → "tmux-agent
  does not create sessions; it **opens worker panes** in the current
  window with `split`." Update the "Session and pane management" section
  with the `split → name → read → type → keys` chain.
- **CLAUDE.md**: one line under "Architecture" documenting the new command.

## Tests

New `tests/tmux-agent/split.bats`:

1. `split` creates a pane and prints a valid pane-id (`%\d+`).
2. The new pane is in the same window as the caller.
3. `--cwd <dir>` → the pane is born in that directory (verify via `list`).
4. `-v` → vertical split (verify orientation).
5. `--target <window>` → splits the correct window.
6. Outside tmux without `--target` → error and non-zero exit.

Plus the standard pre-commit checks:

```bash
bash -n install.sh scripts/tmux-agent
shellcheck install.sh scripts/tmux-agent
bats tests/tmux-agent/
```

## Versioning & release

Minor feature bump `1.13.1 → 1.14.0` in `install.sh` and
`scripts/tmux-agent`. After pushing `main`, create and push the matching
tag `v1.14.0` (release rule: `install.sh` downloads from `v${VERSION}`).
