#!/usr/bin/env bats

INSTALL_SH="$BATS_TEST_DIRNAME/../../install.sh"
FIXTURES="$BATS_TEST_DIRNAME/../fixtures/bin"

setup() {
  export HOME
  HOME="$(mktemp -d)"
  export SHELL=/bin/bash
  export PATH="$FIXTURES:/usr/bin:/bin"
  PROJECT_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$HOME" "$PROJECT_DIR"
}

@test "agent-mux install creates neutral skill path" {
  run bash "$INSTALL_SH" install --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT_DIR/skills/agent-mux/SKILL.md" ]
}

@test "agent-mux install creates claude skill path" {
  run bash "$INSTALL_SH" install --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT_DIR/.claude/skills/agent-mux/SKILL.md" ]
}

@test "agent-mux install creates neutral references" {
  run bash "$INSTALL_SH" install --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT_DIR/skills/agent-mux/references/protocol.md" ]
  [ -f "$PROJECT_DIR/skills/agent-mux/references/orchestration.md" ]
  [ -f "$PROJECT_DIR/skills/agent-mux/references/tmux-agent.md" ]
  [ -f "$PROJECT_DIR/skills/agent-mux/references/tmux.md" ]
}

@test "agent-mux install creates claude references" {
  run bash "$INSTALL_SH" install --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT_DIR/.claude/skills/agent-mux/references/protocol.md" ]
  [ -f "$PROJECT_DIR/.claude/skills/agent-mux/references/orchestration.md" ]
  [ -f "$PROJECT_DIR/.claude/skills/agent-mux/references/tmux-agent.md" ]
  [ -f "$PROJECT_DIR/.claude/skills/agent-mux/references/tmux.md" ]
}

@test "agent-mux install creates compact skill entrypoint" {
  run bash "$INSTALL_SH" install --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  grep -q 'tmux-agent protocol' "$PROJECT_DIR/skills/agent-mux/SKILL.md"
  grep -q 'tmux-agent protocol' "$PROJECT_DIR/.claude/skills/agent-mux/SKILL.md"
}

@test "agent-mux install accepts --project-dir" {
  other_dir="$(mktemp -d)"
  run bash "$INSTALL_SH" install --project-dir "$other_dir"
  [ "$status" -eq 0 ]
  [ -f "$other_dir/skills/agent-mux/SKILL.md" ]
  rm -rf "$other_dir"
}

@test "tracked markdown has no tmux-bridge references" {
  repo="$BATS_TEST_DIRNAME/../.."
  run bash -c 'cd "$1" && git ls-files "*.md" | xargs grep -n "tmux-bridge"' _ "$repo"
  [ "$status" -ne 0 ]
}
