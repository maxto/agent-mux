#!/usr/bin/env bats

INSTALL_SH="$BATS_TEST_DIRNAME/../../install.sh"
FIXTURES="$BATS_TEST_DIRNAME/../fixtures/bin"

setup() {
  export HOME
  HOME="$(mktemp -d)"
  export SHELL=/bin/bash
  export PATH="$FIXTURES:/usr/bin:/bin"
  PROJECT_DIR="$(mktemp -d)"
  export CURL_LOG="$HOME/curl.log"
}

teardown() {
  rm -rf "$HOME" "$PROJECT_DIR"
}

old_installer() {
  local dest="$HOME/agent-mux-old"
  sed 's/^VERSION="[^"]*"/VERSION="1.2.3"/' "$INSTALL_SH" > "$dest"
  chmod +x "$dest"
  printf '%s\n' "$dest"
}

@test "update reports version from downloaded CLI" {
  installer="$(old_installer)"

  run bash "$installer" update

  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-mux updated to v1.4.0!"* ]]
}

@test "update refreshes project skills from main" {
  mkdir -p "$PROJECT_DIR/skills/agent-mux"
  installer="$(old_installer)"

  run bash -c 'cd "$1" && bash "$2" update' _ "$PROJECT_DIR" "$installer"

  [ "$status" -eq 0 ]
  grep -q 'raw.githubusercontent.com/maxto/agent-mux/main/skills/agent-mux/SKILL.md' "$CURL_LOG"
  ! grep -q 'raw.githubusercontent.com/maxto/agent-mux/v1.2.3/skills/agent-mux/SKILL.md' "$CURL_LOG"
}
