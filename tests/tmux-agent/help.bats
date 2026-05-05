#!/usr/bin/env bats

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

@test "--help shows tmux-agent usage" {
  run bash "$TMUX_AGENT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: tmux-agent"* ]]
  [[ "$output" == *"send <target> <text>"* ]]
}

@test "help subcommand points users to --help" {
  run bash "$TMUX_AGENT" help
  [ "$status" -ne 0 ]
  [[ "$output" == *"Run 'tmux-agent --help' for usage."* ]]
}

@test "protocol shows minimal reply rules without tmux" {
  unset TMUX TMUX_PANE TMUX_AGENT_SOCKET
  run bash "$TMUX_AGENT" protocol
  [ "$status" -eq 0 ]
  [[ "$output" == *"tmux-agent protocol v1"* ]]
  [[ "$output" == *"reply="* ]]
  [[ "$output" == *"tmux-agent send"* ]]
  [[ "$output" == *"tmux-agent task"* ]]
  [[ "$output" == *"Do not wait"* ]]
}
