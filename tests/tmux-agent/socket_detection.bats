#!/usr/bin/env bats

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  MOCK_BIN="$BATS_TMPDIR/socket-detect-bin-$BATS_TEST_NUMBER"
  mkdir -p "$MOCK_BIN"
  cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-S" && "${2:-}" == "/tmp/bad.sock" && "${3:-}" == "list-sessions" ]]; then
  exit 1
fi

if [[ "${1:-}" == "display-message" && "$*" == *"#{socket_path}"* ]]; then
  printf '/tmp/good.sock\n'
  exit 0
fi

if [[ "${1:-}" == "-S" && "${2:-}" == "/tmp/good.sock" && "${3:-}" == "list-panes" ]]; then
  printf '%%1|test|0|agents|12345|80x24|claude|/tmp\n'
  exit 0
fi

exit 0
EOF
  chmod +x "$MOCK_BIN/tmux"
  export PATH="$MOCK_BIN:/usr/bin:/bin"
  export TMUX="/tmp/bad.sock,123,0"
  export TMUX_PANE="%1"
  unset TMUX_AGENT_SOCKET
}

teardown() {
  rm -rf "$MOCK_BIN"
}

@test "detect_socket falls back to display-message when TMUX -S check fails" {
  run bash "$TMUX_AGENT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"%1"* ]]
  [[ "$output" == *"claude"* ]]
}
