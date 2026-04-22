#!/usr/bin/env bash
# agent-mux — one-command tmux setup
set -euo pipefail

VERSION="1.1.4"
REPO="maxto/agent-mux"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
SMUX_DIR="$HOME/.agent-mux"
BIN_DIR="$SMUX_DIR/bin"
BACKUP_DIR="$SMUX_DIR/backups"
TMUX_XDG_DIR="$HOME/.config/tmux"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { printf "${GREEN}[agent-mux]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[agent-mux]${NC} %s\n" "$*"; }
error() { printf "${RED}[agent-mux]${NC} %s\n" "$*" >&2; exit 1; }

# --- OS / package manager detection ---

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      error "Unsupported OS: $(uname -s)" ;;
  esac
}

detect_pkg_manager() {
  if command -v brew >/dev/null 2>&1; then echo "brew"
  elif command -v apt-get >/dev/null 2>&1; then echo "apt"
  elif command -v dnf >/dev/null 2>&1; then echo "dnf"
  elif command -v pacman >/dev/null 2>&1; then echo "pacman"
  elif command -v apk >/dev/null 2>&1; then echo "apk"
  else echo "unknown"
  fi
}

pkg_install() {
  local pkg="$1"
  local mgr
  mgr=$(detect_pkg_manager)
  info "Installing $pkg via $mgr..."
  case "$mgr" in
    brew)   brew install "$pkg" ;;
    apt)    sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg" ;;
    dnf)    sudo dnf install -y -q "$pkg" ;;
    pacman) sudo pacman -S --noconfirm "$pkg" ;;
    apk)    sudo apk add "$pkg" ;;
    *)      error "No supported package manager found. Install $pkg manually and re-run." ;;
  esac
}

# --- Helpers ---

check_tmux_version() {
  local ver
  ver=$(tmux -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
  local major minor
  major=$(echo "$ver" | cut -d. -f1)
  minor=$(echo "$ver" | cut -d. -f2)
  if (( major < 3 || (major == 3 && minor < 2) )); then
    warn "tmux $ver detected. Version 3.2+ recommended for full visual features."
  fi
}

backup_existing() {
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$BACKUP_DIR"

  # Check XDG location
  if [[ -f "$TMUX_XDG_DIR/tmux.conf" && ! -L "$TMUX_XDG_DIR/tmux.conf" ]]; then
    cp "$TMUX_XDG_DIR/tmux.conf" "$BACKUP_DIR/tmux.conf.$ts"
    info "Backed up ~/.config/tmux/tmux.conf → ~/.agent-mux/backups/tmux.conf.$ts"
  fi

  # Check legacy location
  if [[ -f "$HOME/.tmux.conf" ]]; then
    cp "$HOME/.tmux.conf" "$BACKUP_DIR/tmux.conf.legacy.$ts"
    info "Backed up ~/.tmux.conf → ~/.agent-mux/backups/tmux.conf.legacy.$ts"
  fi
}

ensure_path() {
  if echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
    return
  fi

  local rc_file=""
  case "${SHELL:-/bin/bash}" in
    */zsh)  rc_file="$HOME/.zshrc" ;;
    */bash) rc_file="$HOME/.bashrc" ;;
    *)      rc_file="$HOME/.profile" ;;
  esac

  local path_line='export PATH="$HOME/.agent-mux/bin:$PATH"'

  if [[ -f "$rc_file" ]] && grep -qF '.agent-mux/bin' "$rc_file"; then
    return
  fi

  info "Adding ~/.agent-mux/bin to PATH in $rc_file"
  echo "" >> "$rc_file"
  echo "# agent-mux" >> "$rc_file"
  echo "$path_line" >> "$rc_file"
  export PATH="$BIN_DIR:$PATH"
}


download() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    error "Neither curl nor wget found. Install one and re-run."
  fi
}

# --- Commands ---

install_skill() {
  local project_dir="$1"

  # Neutral path — readable by any agent (Codex /init, Gemini @path, aider /add, etc.)
  local neutral_dir="$project_dir/skills/agent-mux"
  info "Installing agent-mux skill to ${neutral_dir/#$HOME/\~}..."
  mkdir -p "$neutral_dir/references"
  download "$BASE_URL/skills/agent-mux/SKILL.md"                    "$neutral_dir/SKILL.md"
  download "$BASE_URL/skills/agent-mux/references/tmux-agent.md"   "$neutral_dir/references/tmux-agent.md"
  download "$BASE_URL/skills/agent-mux/references/tmux.md"          "$neutral_dir/references/tmux.md"

  # Claude Code path — enables /agent-mux slash command
  local claude_dir="$project_dir/.claude/skills/agent-mux"
  info "Installing Claude Code skill to ${claude_dir/#$HOME/\~}..."
  mkdir -p "$claude_dir/references"
  download "$BASE_URL/skills/agent-mux/SKILL.md"                    "$claude_dir/SKILL.md"
  download "$BASE_URL/skills/agent-mux/references/tmux-agent.md"   "$claude_dir/references/tmux-agent.md"
  download "$BASE_URL/skills/agent-mux/references/tmux.md"          "$claude_dir/references/tmux.md"
}

cmd_install() {
  local with_config=false
  local project_dir="$PWD"
  local args=("$@")
  local i=0
  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      --with-config) with_config=true ;;
      --project-dir) i=$(( i + 1 )); project_dir="${args[$i]}" ;;
    esac
    i=$(( i + 1 ))
  done

  local os
  os=$(detect_os)
  info "Installing agent-mux ($os)..."

  # 1. Install tmux if missing
  if ! command -v tmux >/dev/null 2>&1; then
    info "tmux not found. Installing..."
    if [[ "$os" == "macos" ]] && ! command -v brew >/dev/null 2>&1; then
      error "Homebrew is required to install tmux on macOS. Install it from https://brew.sh and re-run."
    fi
    pkg_install tmux
  fi
  check_tmux_version

  # 2. Install clipboard tool on Linux if missing
  if [[ "$os" == "linux" ]]; then
    if ! command -v xclip >/dev/null 2>&1 && ! command -v xsel >/dev/null 2>&1; then
      info "No clipboard tool found. Installing xclip..."
      pkg_install xclip
    fi
  fi

  # 3. Create directories
  mkdir -p "$SMUX_DIR" "$BIN_DIR"
  download "$BASE_URL/help.txt" "$SMUX_DIR/help.txt"

  # 4. Download and symlink tmux config (opt-in only)
  if [[ "$with_config" == true ]]; then
    warn "Your existing tmux config will be replaced with a symlink to ~/.agent-mux/tmux.conf"
    warn "Backups are stored in ~/.agent-mux/backups/"
    backup_existing
    info "Downloading tmux.conf..."
    download "$BASE_URL/.tmux.conf" "$SMUX_DIR/tmux.conf"
    mkdir -p "$TMUX_XDG_DIR"
    ln -sf "$SMUX_DIR/tmux.conf" "$TMUX_XDG_DIR/tmux.conf"
  fi

  # 5. Download tmux-agent
  info "Downloading tmux-agent..."
  download "$BASE_URL/scripts/tmux-agent" "$BIN_DIR/tmux-agent"
  chmod +x "$BIN_DIR/tmux-agent"

  # 6. Save agent-mux CLI (download to tmp then mv — avoids self-overwrite if running from PATH)
  info "Installing agent-mux CLI..."
  download "$BASE_URL/install.sh" "$BIN_DIR/agent-mux.tmp"
  mv "$BIN_DIR/agent-mux.tmp" "$BIN_DIR/agent-mux"
  chmod +x "$BIN_DIR/agent-mux"

  # 7. Install skill (neutral + Claude Code paths)
  install_skill "$project_dir"

  # 8. Ensure PATH
  ensure_path

  # 9. Reload tmux config if running and config was installed
  if [[ "$with_config" == true ]] && tmux list-sessions &>/dev/null; then
    tmux source-file "$SMUX_DIR/tmux.conf" 2>/dev/null && info "Reloaded tmux config." || true
  fi

  # 10. Done
  local neutral_rel="${project_dir/#$HOME/\~}/skills/agent-mux"
  local claude_rel="${project_dir/#$HOME/\~}/.claude/skills/agent-mux"
  echo ""
  printf "${GREEN}${BOLD}agent-mux installed!${NC}\n"
  echo ""
  if [[ "$with_config" == true ]]; then
    echo "  Config:         ~/.agent-mux/tmux.conf"
  fi
  echo "  tmux-agent:     ~/.agent-mux/bin/tmux-agent"
  echo "  agent-mux CLI:  ~/.agent-mux/bin/agent-mux"
  echo "  skill (neutral):  $neutral_rel"
  echo "  skill (claude):   $claude_rel"
  if [[ "$with_config" != true ]]; then
    echo ""
    echo "  Tip: run 'agent-mux install --with-config' to also install the tmux config."
  fi
  echo ""
  echo "  Run 'agent-mux help' for commands."
  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
    echo ""
    warn "Restart your shell or run: export PATH=\"\$HOME/.agent-mux/bin:\$PATH\""
  fi
}

cmd_update() {
  info "Updating agent-mux..."

  mkdir -p "$SMUX_DIR" "$BIN_DIR"
  download "$BASE_URL/help.txt" "$SMUX_DIR/help.txt"

  info "Downloading tmux-agent..."
  download "$BASE_URL/scripts/tmux-agent" "$BIN_DIR/tmux-agent"
  chmod +x "$BIN_DIR/tmux-agent"

  info "Updating agent-mux CLI..."
  download "$BASE_URL/install.sh" "$BIN_DIR/agent-mux.tmp"
  mv "$BIN_DIR/agent-mux.tmp" "$BIN_DIR/agent-mux"
  chmod +x "$BIN_DIR/agent-mux"

  if [[ -d "$PWD/.claude/skills/agent-mux" ]] || [[ -d "$PWD/skills/agent-mux" ]]; then
    info "Updating agent-mux skill..."
    install_skill "$PWD"
  fi

  # Only update tmux config if user previously opted into --with-config
  # (symlink exists AND points to our file — not a user-managed symlink)
  if [[ -L "$TMUX_XDG_DIR/tmux.conf" ]] && \
     [[ "$(readlink "$TMUX_XDG_DIR/tmux.conf")" == "$SMUX_DIR/tmux.conf" ]]; then
    mkdir -p "$BACKUP_DIR"
    backup_existing
    info "Downloading tmux.conf..."
    download "$BASE_URL/.tmux.conf" "$SMUX_DIR/tmux.conf"
    if tmux list-sessions &>/dev/null; then
      tmux source-file "$SMUX_DIR/tmux.conf" 2>/dev/null && info "Reloaded tmux config." || true
    fi
  fi

  printf "${GREEN}${BOLD}agent-mux updated to v${VERSION}!${NC}\n"
}

cmd_uninstall() {
  info "Uninstalling agent-mux..."

  # Remove symlink
  if [[ -L "$TMUX_XDG_DIR/tmux.conf" ]]; then
    rm "$TMUX_XDG_DIR/tmux.conf"
    info "Removed symlink ~/.config/tmux/tmux.conf"
  fi

  # Check for backups to restore
  local latest_backup
  latest_backup=$(ls -t "$BACKUP_DIR"/tmux.conf.* 2>/dev/null | head -1 || true)
  if [[ -n "$latest_backup" ]]; then
    info "Restoring backup: $latest_backup"
    mkdir -p "$TMUX_XDG_DIR"
    cp "$latest_backup" "$TMUX_XDG_DIR/tmux.conf"
  fi

  # Remove agent-mux directory
  rm -rf "$SMUX_DIR"
  info "Removed ~/.agent-mux/"

  echo ""
  printf "${GREEN}${BOLD}agent-mux uninstalled.${NC}\n"
  echo ""
  echo "  Note: You may want to remove the PATH line from your shell rc file:"
  echo "    export PATH=\"\$HOME/.agent-mux/bin:\$PATH\""
}

cmd_version() {
  echo "agent-mux $VERSION"
}

cmd_help() {
  local help_file="$SMUX_DIR/help.txt"
  if [[ -f "$help_file" ]]; then
    cat "$help_file"
  else
    error "Help file not found. Run 'agent-mux update' to install it."
  fi
}

cmd_cli_ref() {
  cat <<'EOF'
agent-mux — one-command tmux setup

Usage: agent-mux <command> [flags]

Commands:
  install [--with-config]            Install agent-mux
    [--project-dir <path>]             Installs tmux-agent, agent-mux CLI, and the skill
                                       into two paths in the current dir (or --project-dir):
                                         skills/agent-mux/        neutral — any agent
                                         .claude/skills/agent-mux/ Claude Code /agent-mux
                                       --with-config: also installs the agent-mux tmux config
                                       and symlinks it to ~/.config/tmux/tmux.conf.
                                       Your existing config is backed up to ~/.agent-mux/backups/.
  update                    Update tmux-agent, agent-mux CLI, and tmux.conf to latest
  uninstall                 Remove agent-mux and restore previous tmux config (if backed up)
  version                   Print version
  help                      Show tmux-agent and keybinding cheatsheet
  --help                    Show this CLI reference

Files:
  ~/.agent-mux/tmux.conf              tmux configuration (downloaded by --with-config)
  ~/.agent-mux/bin/tmux-agent         cross-pane communication CLI
  ~/.agent-mux/bin/agent-mux          this CLI
  ~/.agent-mux/backups/               config backups (created by --with-config)
  skills/agent-mux/                   skill — neutral path (any agent)
  .claude/skills/agent-mux/           skill — Claude Code /agent-mux slash command
EOF
}

# --- Main ---

# When invoked with no arguments:
# - first-time install (piped via curl | bash): default to install
# - already installed (agent-mux binary exists in PATH): default to help
_default_cmd() {
  if [[ -d "$HOME/.agent-mux" && -x "$HOME/.agent-mux/bin/agent-mux" ]]; then
    cmd_cli_ref
  else
    cmd_install "$@"
  fi
}

case "${1:-}" in
  "")                              _default_cmd "$@" ;;
  install)                         cmd_install "${@:2}" ;;
  update)                          cmd_update ;;
  uninstall|remove)                cmd_uninstall ;;
  version|--version|-v|-V)         cmd_version ;;
  help|cheatsheet|cheat|keys)      cmd_help ;;
  --help|-h|commands)              cmd_cli_ref ;;
  *)                               error "Unknown command: $1. Run 'agent-mux help' for cheatsheet, 'agent-mux --help' for all commands." ;;
esac
