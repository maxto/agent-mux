#!/usr/bin/env bats

INSTALL_SH="$BATS_TEST_DIRNAME/../../install.sh"
FIXTURES="$BATS_TEST_DIRNAME/../fixtures/bin"

setup() {
  export HOME
  HOME="$(mktemp -d)"
  export SHELL=/bin/bash
  export PATH="$FIXTURES:/usr/bin:/bin"
  export TMUX_FIXTURE_LOG="$BATS_TMPDIR/tmux-session-$BATS_TEST_NUMBER.log"
  unset TMUX TMUX_PANE TMUX_AGENT_SOCKET TMUX_FIXTURE_HAS_SESSION
}

teardown() {
  rm -rf "$HOME"
  rm -f "$TMUX_FIXTURE_LOG"
}

@test "session help shows usage" {
  run bash "$INSTALL_SH" session --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-mux session"* ]]
  [[ "$output" == *"--labels a,b,c"* ]]
  [[ "$output" == *"session kill"* ]]
}

@test "session without subcommand shows usage without creating or attaching" {
  run bash "$INSTALL_SH" session
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-mux session"* ]]
  ! grep -q "new-session" "$TMUX_FIXTURE_LOG"
  ! grep -q "split-window" "$TMUX_FIXTURE_LOG"
  ! grep -q "attach-session" "$TMUX_FIXTURE_LOG"
}

@test "session rejects options without explicit start" {
  run bash "$INSTALL_SH" session --labels lead,reviewer
  [ "$status" -ne 0 ]
  [[ "$output" == *"agent-mux session start --labels lead,reviewer"* ]]
  ! grep -q "new-session" "$TMUX_FIXTURE_LOG"
}

@test "session start outside tmux creates named session without attaching" {
  run bash "$INSTALL_SH" session start --name custom
  [ "$status" -eq 0 ]
  grep -q "new-session -d -s custom -n agents" "$TMUX_FIXTURE_LOG"
  ! grep -q "attach-session -t custom" "$TMUX_FIXTURE_LOG"
  [[ "$output" == *"Run: agent-mux attach custom"* ]]
}

@test "session start outside tmux applies variable custom labels" {
  run bash "$INSTALL_SH" session start --labels lead,reviewer,tester,bash
  [ "$status" -eq 0 ]
  grep -q "set-option -p -t %1 @name lead" "$TMUX_FIXTURE_LOG"
  grep -q "set-option -p -t %2 @name reviewer" "$TMUX_FIXTURE_LOG"
  grep -q "@name tester" "$TMUX_FIXTURE_LOG"
  grep -q "@name bash" "$TMUX_FIXTURE_LOG"
}

@test "session start outside tmux leaves existing session untouched without attaching" {
  export TMUX_FIXTURE_HAS_SESSION=0
  run bash "$INSTALL_SH" session start --name existing
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
  [[ "$output" == *"agent-mux attach existing"* ]]
  ! grep -q "attach-session -t existing" "$TMUX_FIXTURE_LOG"
  ! grep -q "new-session -d -s existing" "$TMUX_FIXTURE_LOG"
}

@test "session rejects empty label" {
  run bash "$INSTALL_SH" session start --labels one,,two
  [ "$status" -ne 0 ]
  [[ "$output" == *"one or more comma-separated labels"* ]]
}

@test "session rejects trailing comma in labels" {
  run bash "$INSTALL_SH" session start --labels one,two,three,
  [ "$status" -ne 0 ]
  [[ "$output" == *"one or more comma-separated labels"* ]]
}

@test "session start outside tmux launches matching commands" {
  run bash "$INSTALL_SH" session start --labels qwen,deepseek --cmds "qwen,ollama run deepseek"
  [ "$status" -eq 0 ]
  grep -q "send-keys -t %1 -l -- qwen" "$TMUX_FIXTURE_LOG"
  grep -q "send-keys -t %2 -l -- ollama run deepseek" "$TMUX_FIXTURE_LOG"
}

@test "session start outside tmux prints created layout before attach" {
  run bash "$INSTALL_SH" session start --labels lead,reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"lead: %1"* ]]
  [[ "$output" == *"reviewer: %2"* ]]
}

@test "session rejects command count mismatch" {
  run bash "$INSTALL_SH" session start --labels qwen,deepseek --cmds qwen
  [ "$status" -ne 0 ]
  [[ "$output" == *"--cmds count must match --labels count"* ]]
}

@test "session list shows tmux sessions" {
  export TMUX_FIXTURE_LIST_SESSIONS=$'agents|1|1\ncrm|1|0'
  run bash "$INSTALL_SH" session list
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents"* ]]
  [[ "$output" == *"crm"* ]]
}

@test "session list prints header with no sessions" {
  run bash "$INSTALL_SH" session list
  [ "$status" -eq 0 ]
  [[ "$output" == *"SESSION"* ]]
}

@test "session kill accepts --name" {
  export TMUX_FIXTURE_HAS_SESSION=0
  run bash "$INSTALL_SH" session kill --name oldagents
  [ "$status" -eq 0 ]
  grep -q "kill-session -t oldagents" "$TMUX_FIXTURE_LOG"
}

@test "session kill requires a session name" {
  run bash "$INSTALL_SH" session kill
  [ "$status" -ne 0 ]
  [[ "$output" == *"session kill requires"* ]]
}

@test "attach accepts positional session name" {
  export TMUX_FIXTURE_HAS_SESSION=0
  run bash "$INSTALL_SH" attach custom
  [ "$status" -eq 0 ]
  grep -q "attach-session -t custom" "$TMUX_FIXTURE_LOG"
}

@test "attach accepts --name" {
  export TMUX_FIXTURE_HAS_SESSION=0
  run bash "$INSTALL_SH" attach --name custom
  [ "$status" -eq 0 ]
  grep -q "attach-session -t custom" "$TMUX_FIXTURE_LOG"
}

@test "attach rejects two positional names" {
  export TMUX_FIXTURE_HAS_SESSION=0
  run bash "$INSTALL_SH" attach agents agents
  [ "$status" -ne 0 ]
  [[ "$output" == *"attach accepts only one session name"* ]]
  ! grep -q "attach-session" "$TMUX_FIXTURE_LOG"
}

@test "open is an alias for attach" {
  export TMUX_FIXTURE_HAS_SESSION=0
  run bash "$INSTALL_SH" open custom
  [ "$status" -eq 0 ]
  grep -q "attach-session -t custom" "$TMUX_FIXTURE_LOG"
}

@test "attach requires an existing session" {
  run bash "$INSTALL_SH" attach missing
  [ "$status" -ne 0 ]
  [[ "$output" == *"session not found: missing"* ]]
  ! grep -q "attach-session -t missing" "$TMUX_FIXTURE_LOG"
}
