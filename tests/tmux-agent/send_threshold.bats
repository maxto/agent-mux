#!/usr/bin/env bats
# Tests for TMUX_AGENT_INLINE_THRESHOLD — controls the auto-spill boundary in cmd_send.
# Uses the 'tmux-agent threshold' subcommand (no live tmux session required).

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  unset TMUX_AGENT_INLINE_THRESHOLD
  export TMUX_PANE="%1"
}

# ── default threshold ─────────────────────────────────────────────────────────

@test "threshold: default is 2048" {
  run bash "$TMUX_AGENT" threshold
  [ "$status" -eq 0 ]
  [ "$output" = "2048" ]
}

@test "threshold: explicit 2048 matches default" {
  TMUX_AGENT_INLINE_THRESHOLD=2048 run bash "$TMUX_AGENT" threshold
  [ "$status" -eq 0 ]
  [ "$output" = "2048" ]
}

# ── threshold=0 forces always-file transport ──────────────────────────────────

@test "threshold: 0 is valid (always-file mode)" {
  TMUX_AGENT_INLINE_THRESHOLD=0 run bash "$TMUX_AGENT" threshold
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# ── higher threshold keeps medium payloads inline ─────────────────────────────

@test "threshold: 4096 accepted (payload >2048 but <4096 stays inline)" {
  TMUX_AGENT_INLINE_THRESHOLD=4096 run bash "$TMUX_AGENT" threshold
  [ "$status" -eq 0 ]
  [ "$output" = "4096" ]
}

# ── lower threshold spills smaller payloads ───────────────────────────────────

@test "threshold: 1024 accepted (payload >1024 auto-spills)" {
  TMUX_AGENT_INLINE_THRESHOLD=1024 run bash "$TMUX_AGENT" threshold
  [ "$status" -eq 0 ]
  [ "$output" = "1024" ]
}

# ── invalid values fail with clear error ──────────────────────────────────────

@test "threshold: non-integer fails with clear error" {
  TMUX_AGENT_INLINE_THRESHOLD=abc run bash "$TMUX_AGENT" threshold
  [ "$status" -ne 0 ]
  [[ "$output" == *"TMUX_AGENT_INLINE_THRESHOLD"* ]]
  [[ "$output" == *"non-negative integer"* ]]
}

@test "threshold: negative value fails with clear error" {
  TMUX_AGENT_INLINE_THRESHOLD=-1 run bash "$TMUX_AGENT" threshold
  [ "$status" -ne 0 ]
  [[ "$output" == *"TMUX_AGENT_INLINE_THRESHOLD"* ]]
}

@test "threshold: float fails with clear error" {
  TMUX_AGENT_INLINE_THRESHOLD=2.5 run bash "$TMUX_AGENT" threshold
  [ "$status" -ne 0 ]
  [[ "$output" == *"TMUX_AGENT_INLINE_THRESHOLD"* ]]
}

@test "threshold: empty string fails with clear error" {
  TMUX_AGENT_INLINE_THRESHOLD="" run bash "$TMUX_AGENT" threshold
  [ "$status" -ne 0 ]
  [[ "$output" == *"TMUX_AGENT_INLINE_THRESHOLD"* ]]
}
