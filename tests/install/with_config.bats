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

@test "install creates tmux.conf symlink by default" {
  run bash "$INSTALL_SH" install --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/tmux/tmux.conf" ]
}

@test "install tmux.conf symlink points to agent-mux tmux.conf" {
  run bash "$INSTALL_SH" install --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  target=$(readlink "$HOME/.config/tmux/tmux.conf")
  [ "$target" = "$HOME/.agent-mux/tmux.conf" ]
}

@test "install downloads tmux.conf by default" {
  run bash "$INSTALL_SH" install --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.agent-mux/tmux.conf" ]
}

@test "install backs up existing regular tmux.conf by default" {
  mkdir -p "$HOME/.config/tmux"
  echo "existing config" > "$HOME/.config/tmux/tmux.conf"
  run bash "$INSTALL_SH" install --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  count=$(ls "$HOME/.agent-mux/backups/" | grep -c 'tmux.conf\.')
  [ "$count" -gt 0 ]
}

@test "install does not back up existing agent-mux symlink" {
  mkdir -p "$HOME/.config/tmux" "$HOME/.agent-mux"
  echo "# placeholder" > "$HOME/.agent-mux/tmux.conf"
  ln -s "$HOME/.agent-mux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
  run bash "$INSTALL_SH" install --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  count=$(ls "$HOME/.agent-mux/backups/" 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 0 ]
}

@test "install records replaced non-agent-mux symlink target" {
  mkdir -p "$HOME/.config/tmux"
  ln -s "$HOME/.mxmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
  run bash "$INSTALL_SH" install --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  grep -q '/.mxmux/tmux.conf' "$HOME"/.agent-mux/backups/tmux.conf.symlink.*
}

@test "--with-config remains accepted" {
  run bash "$INSTALL_SH" install --with-config --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/tmux/tmux.conf" ]
}

@test "--no-config skips tmux.conf symlink" {
  run bash "$INSTALL_SH" install --no-config --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/tmux/tmux.conf" ]
}

@test "--config=false skips tmux.conf symlink" {
  run bash "$INSTALL_SH" install --config=false --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/tmux/tmux.conf" ]
}
