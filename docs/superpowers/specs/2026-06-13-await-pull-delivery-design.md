# Design: `tmux-agent await` — pull-based delivery with sentinel

Date: 2026-06-13
Status: approved in brainstorming, ready for implementation plan
Target version: **v1.13.0** (MINOR — new command with tests + docs)

## Problem

Message delivery in agent-mux is currently a **direct push onto a TUI**: the
sender physically types the message into the recipient's pane via
`tmux send-keys` and presses Enter (`cmd_send` → `submit_enter`). This produces
two defects:

- **P1 — the worker cannot reply.** `send` only prepends the `reply=%3` header.
  A non-skill-aware worker (Codex, Gemini, DeepSeek, small local models) reads it
  as ordinary text and answers "out loud" in its own pane instead of running
  `tmux-agent send %3 '...'`. It is a bare CLI: it does not know the protocol.
- **P2 — race / busy recipient.** If Claude is still generating when the worker
  replies, the keystrokes land in the input box but the Enter may not be
  accepted; the reply is lost or left hanging. Behavior is inconsistent and hard
  to isolate.

Both stem from the same root: push delivery requires the recipient to be idle
**and** to understand the protocol.

## Core idea

Flip the model for the **worker → Claude** direction: workers never route the
reply. Claude **delegates in pull mode** and then **pulls** the reply when it is
ready.

- No text is ever injected into Claude's pane → **P2 eliminated at the root** (no
  race, no lost Enter).
- The worker merely prints its reply in its own pane wrapped between two
  sentinels → works with **any agent without knowing the protocol** →
  **P1 eliminated**.

The new model **coexists** with the current `send`/reply push (unchanged), which
remains for already-protocol-aware agents (e.g. another Claude in a different
session). Bare panes without an agent do not use `await`: they stay targets of
`type`/`keys`.

## Sentinel protocol

`task --await` appends a footer to the prompt asking the worker to wrap its final
answer between two standalone lines:

```
<<<codex@%4 reply 7a3f>>>
…the answer…
<<<codex@%4 done 7a3f>>>
```

- `codex@%4` = pane label + pane-id (falls back to just `%4` when the pane has no
  label). Makes it readable at a glance whose reply it is.
- `7a3f` = short per-task **nonce**. Not cosmetic: it guarantees that a *stale*
  reply left in the scrollback is not mistaken for the current task's reply.
- Two sentinels (not one): the `reply` marker delimits the start so we can
  **extract only the answer** (token-minimal ingestion), the `done` marker
  signals completion.
- **No namespace prefix**: the nonce alone is enough to avoid collisions.

### Echo handling (hardened Strategy A)

The injected footer literally contains the sentinels, so they appear in the
buffer both in the instruction echo and in the real output. Two measures remove
any false-match risk without sacrificing robustness on weak models:

1. `await` matches a sentinel **only when it is on a line of its own** (anchored
   regex `^<<<codex@%4 done 7a3f>>>$`).
2. The footer writes the instructions with the sentinels **inside prose
   sentences** — never as two isolated lines wrapping content.

Result: the instruction echo never forms a valid `reply`-line + `done`-line pair
with content in between; **only the worker's real output** forms one. Literal
sentinels stay visible to weak models (robustness) with no false match
(precision).

## Handoff via state file

Reuses the marker-file pattern already used by the read-guard.

`tmux-agent task --await %4 '...'`:
1. generates the nonce and computes the full `done` sentinel;
2. injects `prompt + sentinel footer` into the worker's pane (push toward the
   worker: timing is controlled by Claude, hence safe);
3. writes the **expected `done` sentinel (full string)** to
   `/tmp/tmux-agent-await-<pane-id>`.

`tmux-agent await %4` reads the expected sentinel from the file, waits for that
block, then clears the file. Claude **never handles the nonce by hand**, and
`await` **reconstructs nothing**: it searches for the literal expected string
(anchored to a whole line).

## `await` command (multi-target fan-in)

```
tmux-agent await <target...> [--timeout N]
```

- Polls the panes (~0.5s interval) until **every** target reaches a **terminal**
  state: `done` found **or** timeout.
- `--all` is the default and means *"all in a terminal state"*, not *"all
  succeeded"*. No streaming/`--any` mode: it would revert to more round-trips =
  more tokens.
- Global `--timeout` (default **300s**, override `TMUX_AGENT_AWAIT_TIMEOUT`).
- Blocking but **zero token cost while waiting** (bash loop, no generation). A
  slow worker costs at most the timeout, not forever.
- `await` only runs `capture-pane` (read): it **does not consume the read-guard**
  and does not touch `send`/reply.

### Output

Compact and delimited — only the extracted answers (token-minimal):

```
=== reply %4 (codex) ===
…answer…
=== reply %5 (gemini) ===
…answer…
```

On a target timeout:

```
=== TIMEOUT %4 (codex) — no marker after 300s ===
…last pane lines for diagnosis…
```

The target's state file is cleared in both cases.

### Typical flow (fan-in, one turn, one ingestion)

```bash
tmux-agent task --await %4 '...'
tmux-agent task --await %5 '...'
tmux-agent await %4 %5
```

## Surface & constraints

- Two new primitives: `task --await` flag + `await` command. No convenience
  `ask` command (YAGNI).
- `await` captures with enough scrollback to contain the block; extracts **only**
  the text between the last `reply…done` pair carrying that sentinel.
- No daemon, no build: pure bash, consistent with the project ethos.
- Full coexistence with existing `send`/`message`/`reply`: nothing is removed.

## Tests (bats, under `tests/tmux-agent/`)

Mock `tmux capture-pane` to emit a synthetic pane:

- correct extraction of the `reply…done` block;
- **echo handling**: sentinel present both in the instruction echo and in the
  output → match only the real block;
- **timeout**: no marker within `--timeout` → `TIMEOUT` block + state-file
  cleanup;
- **multi-target fan-in**: two targets, one completes and one times out →
  consolidated output with both blocks;
- handoff: `task --await` writes the state file with the correct expected
  sentinel; `await` reads and clears it.

## Documentation

- `tmux-agent protocol` — describe the pull model and when to prefer it over
  push.
- `tmux-agent --help` — `await` entry and `task --await` flag, env
  `TMUX_AGENT_AWAIT_TIMEOUT`.
- `skills/agent-mux/SKILL.md` **and** `.claude/skills/agent-mux/SKILL.md`
  (mandatory sync for the drift test).
- `references/orchestration.md` — pull-delegation pattern for heterogeneous
  workers.

## Versioning

Bump `VERSION` in `install.sh` and `scripts/tmux-agent` to **1.13.0**; after
pushing `main`, create and push the `v1.13.0` tag.
