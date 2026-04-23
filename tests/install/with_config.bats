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

@test "--with-config creates tmux.conf symlink" {
  run bash "$INSTALL_SH" install --with-config --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/tmux/tmux.conf" ]
}

@test "--with-config symlink points to agent-mux tmux.conf" {
  run bash "$INSTALL_SH" install --with-config --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  target=$(readlink "$HOME/.config/tmux/tmux.conf")
  [ "$target" = "$HOME/.agent-mux/tmux.conf" ]
}

@test "--with-config downloads tmux.conf" {
  run bash "$INSTALL_SH" install --with-config --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.agent-mux/tmux.conf" ]
}

@test "--with-config backs up existing regular tmux.conf" {
  mkdir -p "$HOME/.config/tmux"
  echo "existing config" > "$HOME/.config/tmux/tmux.conf"
  run bash "$INSTALL_SH" install --with-config --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  count=$(ls "$HOME/.agent-mux/backups/" | grep -c 'tmux.conf\.')
  [ "$count" -gt 0 ]
}

@test "--with-config does not back up existing symlink" {
  mkdir -p "$HOME/.config/tmux" "$HOME/.agent-mux"
  echo "# placeholder" > "$HOME/.agent-mux/tmux.conf"
  ln -s "$HOME/.agent-mux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
  run bash "$INSTALL_SH" install --with-config --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  count=$(ls "$HOME/.agent-mux/backups/" 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 0 ]
}
