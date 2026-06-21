# tmux-agent split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first-class `tmux-agent split` command that creates a pane in a live window and prints its pane-id, so agents add worker panes through the CLI instead of dropping to raw `tmux split-window`.

**Architecture:** A new `cmd_split` in `scripts/tmux-agent` reuses the existing flag-parsing (`cmd_list`), target-resolution (`resolve_target`/`validate_target`), and tmux-wrapper (`tmx`) helpers. It wraps a single `tmux split-window … -PF '#{pane_id}'` call — the same primitive `agent-mux session start` already uses internally — and echoes the new pane-id. No labeling, no process launch: those stay `name` and `read`/`type`/`keys`.

**Tech Stack:** Pure bash, tmux, bats (tests), shellcheck.

## Global Constraints

- Language: all code, comments, docs, and commit messages in **English**.
- No compound commands; `type` keeps omitting Enter; read-guard must not be weakened.
- Touch only what each task requires; no adjacent refactoring.
- Pre-commit checks must pass: `bash -n install.sh scripts/tmux-agent`, `shellcheck install.sh scripts/tmux-agent`, `bats tests/tmux-agent/`.
- Version bump required (feature): `1.13.1 → 1.14.0` in `install.sh` (line 5) and `scripts/tmux-agent` (line 6); matching tag `v1.14.0` after pushing `main` (release rule — `install.sh` downloads from `v${VERSION}`).
- Default split direction is **horizontal** (`-h`, worker beside caller). Default cwd is the current pane's directory. Default target is the current window.
- Output is **only** the pane-id on stdout (e.g. `%1`), mirroring `cmd_id`.

---

### Task 1: Implement `cmd_split` (command + dispatch + usage) with tests

**Files:**
- Create: `tests/tmux-agent/split.bats`
- Modify: `scripts/tmux-agent` — add `cmd_split` (near `cmd_name`, ~line 1066); add `split` to the dispatch allow-list (line 1537) and the second `case` (after line 1557); add a usage line in `usage()` (after the `resolve` line, ~385).
- Test: `tests/tmux-agent/split.bats`

**Interfaces:**
- Consumes: `require_tmux`, `resolve_target`, `validate_target`, `tmx` (existing helpers in `scripts/tmux-agent`).
- Produces: command `tmux-agent split [--cwd <dir>] [-h|-v] [--target <window>]`; prints the new pane-id (`%N`) to stdout; exit non-zero on error.

- [ ] **Step 1: Write the failing test file**

Create `tests/tmux-agent/split.bats`:

```bash
#!/usr/bin/env bats
# Tests for 'tmux-agent split' — sanctioned pane creation in a live window.
# Requires a real tmux server.

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  SOCKET="$BATS_TMPDIR/tmux-split-$BATS_TEST_NUMBER.sock"
  export XDG_RUNTIME_DIR="$BATS_TMPDIR/xdg-split-$$-$BATS_TEST_NUMBER"
  mkdir -p "$XDG_RUNTIME_DIR"

  tmux -S "$SOCKET" new-session -d -s split_test
  TEST_PANE=$(tmux -S "$SOCKET" list-panes -t split_test -F '#{pane_id}' | head -1)

  export TMUX_AGENT_SOCKET="$SOCKET"
  export TMUX_PANE="$TEST_PANE"
  unset TMUX
}

teardown() {
  tmux -S "$SOCKET" kill-server 2>/dev/null || true
  rm -f "$SOCKET"
  rm -rf "$XDG_RUNTIME_DIR"
}

win0_pane_count() {
  tmux -S "$SOCKET" list-panes -t split_test:0 -F '#{pane_id}' | wc -l | tr -d ' '
}

@test "split creates a pane and prints a valid pane-id" {
  run bash "$TMUX_AGENT" split
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^%[0-9]+$ ]]
  [ "$(win0_pane_count)" -eq 2 ]
}

@test "new pane is in the same window as the caller" {
  run bash "$TMUX_AGENT" split
  [ "$status" -eq 0 ]
  new_pane="$output"
  new_win=$(tmux -S "$SOCKET" display-message -t "$new_pane" -p '#{window_id}')
  caller_win=$(tmux -S "$SOCKET" display-message -t "$TEST_PANE" -p '#{window_id}')
  [ "$new_win" = "$caller_win" ]
}

@test "--cwd sets the new pane's working directory" {
  CWD_DIR="$BATS_TMPDIR/split-cwd-$$"
  mkdir -p "$CWD_DIR"
  run bash "$TMUX_AGENT" split --cwd "$CWD_DIR"
  [ "$status" -eq 0 ]
  new_pane="$output"
  path=$(tmux -S "$SOCKET" display-message -t "$new_pane" -p '#{pane_current_path}')
  [ "$(cd "$path" && pwd -P)" = "$(cd "$CWD_DIR" && pwd -P)" ]
}

@test "-v creates a vertically stacked pane (below the caller)" {
  run bash "$TMUX_AGENT" split -v
  [ "$status" -eq 0 ]
  new_pane="$output"
  pane_top=$(tmux -S "$SOCKET" display-message -t "$new_pane" -p '#{pane_top}')
  [ "$pane_top" -gt 0 ]
}

@test "--target splits the named window, leaving the current window untouched" {
  tmux -S "$SOCKET" new-window -t split_test
  run bash "$TMUX_AGENT" split --target split_test:1
  [ "$status" -eq 0 ]
  target_count=$(tmux -S "$SOCKET" list-panes -t split_test:1 -F '#{pane_id}' | wc -l | tr -d ' ')
  [ "$target_count" -eq 2 ]
  [ "$(win0_pane_count)" -eq 1 ]
}

@test "split outside tmux without --target errors" {
  unset TMUX_PANE
  run bash "$TMUX_AGENT" split
  [ "$status" -ne 0 ]
  [[ "$output" == *"--target"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/tmux-agent/split.bats`
Expected: FAIL — `unknown command: split` (the command does not exist yet).

- [ ] **Step 3: Add `cmd_split` to `scripts/tmux-agent`**

Insert this function immediately after `cmd_name` (after its closing `}` near line 1074):

```bash
cmd_split() {
  require_tmux
  local cwd="" direction="-h" target=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cwd)
        shift
        [[ $# -gt 0 ]] || die "split --cwd requires a directory"
        cwd="$1"
        ;;
      -h) direction="-h" ;;
      -v) direction="-v" ;;
      --target)
        shift
        [[ $# -gt 0 ]] || die "split --target requires a window"
        target="$1"
        ;;
      *)
        die "unknown split option: $1. Use: split [--cwd <dir>] [-h|-v] [--target <window>]"
        ;;
    esac
    shift
  done

  local split_target
  if [[ -n "$target" ]]; then
    split_target=$(resolve_target "$target")
    validate_target "$split_target"
  else
    [[ -n "${TMUX_PANE:-}" ]] || die "split requires --target when run outside tmux"
    split_target="$TMUX_PANE"
  fi

  local args=("$direction" "-t" "$split_target" "-PF" '#{pane_id}')
  [[ -n "$cwd" ]] && args+=("-c" "$cwd")
  tmx split-window "${args[@]}"
}
```

- [ ] **Step 4: Register `split` in both dispatch points**

In the allow-list at line 1537, add `split` so it reads:

```bash
  list|type|send|task|message|msg|read|keys|kill|name|resolve|doctor|await|split) ;;
```

In the second `case` (after the `doctor)` line at 1557, before the closing `esac`), add:

```bash
  split)   shift; cmd_split "$@" ;;
```

- [ ] **Step 5: Add the usage line**

In `usage()`, immediately after the `resolve <label>` line (~384), add:

```
  split [--cwd <dir>] [-h|-v] [--target <window>]
                            Create a pane in the current window; prints its pane-id
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bats tests/tmux-agent/split.bats`
Expected: PASS — all 6 tests.

- [ ] **Step 7: Run syntax + lint + full suite**

Run:
```bash
bash -n scripts/tmux-agent
shellcheck scripts/tmux-agent
bats tests/tmux-agent/
```
Expected: no syntax errors, no shellcheck warnings, all tests pass.

- [ ] **Step 8: Commit**

```bash
git add scripts/tmux-agent tests/tmux-agent/split.bats
git commit -m "$(cat <<'EOF'
feat: add tmux-agent split for sanctioned pane creation

Create a pane in a live window and print its pane-id, so agents add
worker panes through the CLI instead of raw tmux split-window. No
labeling or process launch — those stay 'name' and read/type/keys.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Documentation

**Files:**
- Modify: `install.sh` — `cmd_cli_ref` tmux-agent block (after the `tmux-agent resolve` line, ~869).
- Modify: `skills/agent-mux/SKILL.md` — "Session and pane management" section (~lines 74-83).
- Modify: `CLAUDE.md` — "Architecture" section.

**Interfaces:**
- Consumes: the `tmux-agent split` surface from Task 1 (flags and output contract).
- Produces: nothing code-facing; documentation only.

- [ ] **Step 1: Update `install.sh` cli-ref**

In `cmd_cli_ref`, after the `tmux-agent resolve <label>` line (~869), add:

```
  tmux-agent split [--cwd <dir>] [-h|-v]   Create a pane in the current window; prints pane-id
    [--target <window>]
```

- [ ] **Step 2: Update `skills/agent-mux/SKILL.md`**

Replace the paragraph that currently reads:

```
Use `agent-mux` for user-facing session/window work; `tmux-agent` does not
create sessions or split panes:
```

with:

```
Use `agent-mux` for user-facing session/window work. `tmux-agent` does not
create sessions, but it **does** open worker panes in the current window
with `split` (it prints the new pane-id):
```

Then, after the existing `agent-mux` example block in that section, add a second block showing the in-window worker chain:

````
Add a worker pane to the current window and bring it up in the
coordination layer — no raw tmux needed:

```bash
NEW=$(tmux-agent split)            # create pane, prints %id
tmux-agent name "$NEW" worker      # label it
tmux-agent read "$NEW"             # read-guard
tmux-agent type "$NEW" "python worker.py"
tmux-agent keys "$NEW" Enter       # launch
```
````

- [ ] **Step 3: Update `CLAUDE.md`**

Under "## Architecture", add a short subsection (place it after "### Target resolution"):

```markdown
### Pane creation (`split`)

`tmux-agent split` is the only sanctioned way to add a pane to a live
window. It wraps `tmux split-window … -PF '#{pane_id}'` (the same primitive
`agent-mux session start` uses internally) and prints the new pane-id. It
does not label or launch anything — compose with `name` and
`read`/`type`/`keys`. `agent-mux session start` still never splits the
current window; it only creates new detached sessions.
```

- [ ] **Step 4: Verify docs build/lint cleanly**

Run:
```bash
bash -n install.sh
shellcheck install.sh
```
Expected: no errors (the cli-ref is a heredoc, so this just confirms the script still parses).

- [ ] **Step 5: Commit**

```bash
git add install.sh skills/agent-mux/SKILL.md CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: document tmux-agent split across cli-ref, SKILL, CLAUDE

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Version bump and release

**Files:**
- Modify: `install.sh:5` — `VERSION="1.13.1"` → `VERSION="1.14.0"`
- Modify: `scripts/tmux-agent:6` — `VERSION="1.13.1"` → `VERSION="1.14.0"`

**Interfaces:**
- Consumes: completed Tasks 1-2.
- Produces: a tagged `v1.14.0` release.

- [ ] **Step 1: Bump both VERSION strings**

Edit `install.sh` line 5 and `scripts/tmux-agent` line 6 to `VERSION="1.14.0"`.

- [ ] **Step 2: Verify the bump**

Run: `grep -nE '^VERSION=' install.sh scripts/tmux-agent`
Expected: both show `VERSION="1.14.0"`.

- [ ] **Step 3: Run the full pre-commit suite one last time**

Run:
```bash
bash -n install.sh scripts/tmux-agent
shellcheck install.sh scripts/tmux-agent
bats tests/tmux-agent/ tests/install/
```
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add install.sh scripts/tmux-agent
git commit -m "$(cat <<'EOF'
chore: bump version to 1.14.0 for tmux-agent split

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Push branch, merge to main, tag**

After the branch is merged to `main` (via PR or fast-forward, per the user's preference), push `main` and create the matching tag:

```bash
git push origin main
git tag v1.14.0
git push origin v1.14.0
```
Expected: tag `v1.14.0` exists on the remote (required — `install.sh` downloads release files from `v${VERSION}`).

---

## Self-Review

**Spec coverage:**
- Command surface (`split [--cwd] [-h|-v] [--target]`, prints pane-id) → Task 1 Steps 3-5, tests in Step 1.
- Internal behavior / helper reuse → Task 1 Step 3.
- Read-guard invariant (split needs no guard; new pane needs read before type) → enforced by design (no read-marker code added); documented in SKILL chain (Task 2 Step 2).
- Error handling (outside tmux without `--target`, bad `--cwd`, bad `--target`) → Task 1 Step 3 + test 6; `--cwd`/`--target` errors propagate from tmux/`validate_target`.
- Dispatch + usage → Task 1 Steps 4-5.
- Docs (cli-ref, SKILL, CLAUDE) → Task 2.
- Tests (6 cases) → Task 1 Step 1.
- Versioning/release → Task 3.

All spec sections map to a task. No gaps.

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to" — all code is shown in full.

**Type consistency:** `cmd_split` name matches dispatch (`split) … cmd_split`); flag names (`--cwd`, `-h`, `-v`, `--target`) consistent across function, usage, cli-ref, SKILL, and tests; output contract (`%N` only) matches test assertion `^%[0-9]+$`.
