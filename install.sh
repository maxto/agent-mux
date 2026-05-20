#!/usr/bin/env bash
# agent-mux — one-command tmux setup
set -euo pipefail

VERSION="1.11.1"
REPO="maxto/agent-mux"
BRANCH="v${VERSION}"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
MAIN_URL="https://raw.githubusercontent.com/${REPO}/main"
SMUX_DIR="$HOME/.agent-mux"
BIN_DIR="$SMUX_DIR/bin"
BACKUP_DIR="$SMUX_DIR/backups"
TMUX_XDG_DIR="$HOME/.config/tmux"
CLAUDE_USER_SKILL_DIR="$HOME/.claude/skills/agent-mux"

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

  if [[ -L "$TMUX_XDG_DIR/tmux.conf" ]]; then
    local target
    target=$(readlink "$TMUX_XDG_DIR/tmux.conf")
    if [[ "$target" != "$SMUX_DIR/tmux.conf" ]]; then
      printf '%s\n' "$target" > "$BACKUP_DIR/tmux.conf.symlink.$ts"
      info "Recorded ~/.config/tmux/tmux.conf symlink target → ~/.agent-mux/backups/tmux.conf.symlink.$ts"
    fi
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

  # shellcheck disable=SC2016  # intentional: literal $HOME/$PATH written to rc file
  local path_line='export PATH="$HOME/.agent-mux/bin:$PATH"'

  if [[ -f "$rc_file" ]] && grep -qF '.agent-mux/bin' "$rc_file"; then
    return
  fi

  info "Adding ~/.agent-mux/bin to PATH in $rc_file"
  { echo ""; echo "# agent-mux"; echo "$path_line"; } >> "$rc_file"
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

tmux_cmd() {
  local socket="${TMUX_AGENT_SOCKET:-}"
  if [[ -z "$socket" && -n "${TMUX:-}" ]]; then
    socket="${TMUX%%,*}"
  fi

  if [[ -n "$socket" ]]; then
    tmux -S "$socket" "$@"
  else
    tmux "$@"
  fi
}

session_usage() {
  cat <<'EOF'
agent-mux session — create a detached tmux session

Usage:
  agent-mux session start [--name <session>] [--labels a,b,c] [--cmds x,y,z]
  agent-mux session list
  agent-mux session kill --name <session>

Defaults:
  --name agent
  --labels (none) — a single-pane session

Behavior:
  Running 'agent-mux session' without a subcommand is safe: it only prints this help.
  Always creates a NEW detached session; never splits the current window, even
  when run from inside tmux. Errors if a session with that name already exists.
  With no --labels: one pane, no labels. With --labels: one pane per label,
  split and labeled. --cmds requires --labels and must match the label count.
  --cmds is comma-separated; commands containing literal commas are not supported.
  The session is not attached. Enter it with 'agent-mux attach <name>'.
EOF
}

window_usage() {
  cat <<'EOF'
agent-mux window — manage tmux windows at the agent-mux level

Usage:
  agent-mux window rename <name> [--target <window>]

Examples:
  agent-mux window rename work
  agent-mux window rename logs --target agents:0

Behavior:
  Inside tmux, rename targets the current window by default.
  Outside tmux, pass --target <session:window>.
  Use raw tmux commands only for low-level operations not covered here.
EOF
}

SESSION_LABELS=()
SESSION_CMDS=()
SESSION_PANES=()

parse_session_labels() {
  local raw="$1"
  [[ "$raw" =~ ^[^,]+(,[^,]+)*$ ]] || error "--labels requires one or more comma-separated labels"
  SESSION_LABELS=()

  local rest="$raw" label
  while [[ "$rest" == *,* ]]; do
    label="${rest%%,*}"
    SESSION_LABELS+=("$label")
    rest="${rest#*,}"
  done
  SESSION_LABELS+=("$rest")

  for label in "${SESSION_LABELS[@]}"; do
    if [[ ! "$label" =~ ^[A-Za-z0-9._-]+$ ]]; then
      error "invalid label '$label'. Use letters, numbers, dot, underscore, or dash."
    fi
  done
}

parse_session_cmds() {
  local raw="$1"
  [[ "$raw" =~ ^[^,]+(,[^,]+)*$ ]] || error "--cmds requires one or more comma-separated commands"
  SESSION_CMDS=()

  local rest="$raw" cmd
  while [[ "$rest" == *,* ]]; do
    cmd="${rest%%,*}"
    SESSION_CMDS+=("$cmd")
    rest="${rest#*,}"
  done
  SESSION_CMDS+=("$rest")
}

current_tmux_pane() {
  [[ -n "${TMUX_PANE:-}" ]] || return 1
  tmux_cmd display-message -t "$TMUX_PANE" -p '#{pane_id}' 2>/dev/null
}

label_pane() {
  local pane="$1" label="$2"
  tmux_cmd set-option -p -t "$pane" @name "$label" >/dev/null
}

launch_session_commands() {
  (( ${#SESSION_CMDS[@]} == 0 )) && return

  local i
  for i in "${!SESSION_CMDS[@]}"; do
    tmux_cmd send-keys -t "${SESSION_PANES[$i]}" -l -- "${SESSION_CMDS[$i]}"
    tmux_cmd send-keys -t "${SESSION_PANES[$i]}" Enter
  done
}

print_session_layout() {
  local i
  info "Session layout ready:"
  for i in "${!SESSION_LABELS[@]}"; do
    echo "  ${SESSION_LABELS[$i]}: ${SESSION_PANES[$i]}"
  done
}

# Always creates a NEW detached session, separate from the caller's tmux
# session/window. Errors if a session with the same name already exists.
cmd_session_start_outside() {
  local session_name="$1"
  if tmux_cmd has-session -t "$session_name" 2>/dev/null; then
    error "session '$session_name' already exists. Attach with: agent-mux attach $session_name"
  fi

  local pane last_pane i
  SESSION_PANES=()
  pane=$(tmux_cmd new-session -d -s "$session_name" -n "$session_name" -PF '#{pane_id}')
  SESSION_PANES+=("$pane")
  last_pane="$pane"

  if (( ${#SESSION_LABELS[@]} == 0 )); then
    info "Created tmux session '$session_name' (1 pane). Attach with: agent-mux attach $session_name"
    return
  fi

  for i in "${!SESSION_LABELS[@]}"; do
    if (( i == 0 )); then
      pane="${SESSION_PANES[0]}"
    else
      pane=$(tmux_cmd split-window -h -t "$last_pane" -PF '#{pane_id}')
      SESSION_PANES+=("$pane")
    fi

    label_pane "$pane" "${SESSION_LABELS[$i]}"
    last_pane="$pane"
  done
  tmux_cmd select-layout -t "$session_name" tiled >/dev/null 2>&1 || true
  launch_session_commands
  print_session_layout

  info "Created tmux session '$session_name'. Attach with: agent-mux attach $session_name"
}

cmd_session_list() {
  require_tmux_binary
  printf "%-24s %-8s %-8s\n" "SESSION" "WINDOWS" "ATTACHED"
  local raw
  raw=$(tmux_cmd list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}' 2>/dev/null || true)
  [[ -n "$raw" ]] || return 0
  while IFS='|' read -r name windows attached; do
    printf "%-24s %-8s %-8s\n" "$name" "$windows" "$attached"
  done <<< "$raw"
}

cmd_session_kill() {
  require_tmux_binary
  local session_name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        shift
        [[ $# -gt 0 ]] || error "--name requires a session name"
        session_name="$1"
        ;;
      -*)
        error "Unknown session kill option: $1. Run 'agent-mux session --help'."
        ;;
      *)
        [[ -z "$session_name" ]] || error "session kill accepts only one session name"
        session_name="$1"
        ;;
    esac
    shift
  done

  [[ -n "$session_name" ]] || error "session kill requires --name <session>"
  [[ "$session_name" =~ ^[A-Za-z0-9._-]+$ ]] || error "invalid session name '$session_name'"
  tmux_cmd has-session -t "$session_name" 2>/dev/null || error "session not found: $session_name"
  tmux_cmd kill-session -t "$session_name"
  info "Killed tmux session '$session_name'."
}

cmd_session_start() {
  local session_name="agent"
  local labels=""
  local cmds=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        shift
        [[ $# -gt 0 ]] || error "--name requires a session name"
        session_name="$1"
        ;;
      --labels)
        shift
        [[ $# -gt 0 ]] || error "--labels requires a value"
        labels="$1"
        ;;
      --cmds)
        shift
        [[ $# -gt 0 ]] || error "--cmds requires a value"
        cmds="$1"
        ;;
      *) error "Unknown session start option: $1. Run 'agent-mux session --help'." ;;
    esac
    shift
  done

  [[ "$session_name" =~ ^[A-Za-z0-9._-]+$ ]] || error "invalid session name '$session_name'"
  require_tmux_binary
  SESSION_LABELS=()
  [[ -n "$labels" ]] && parse_session_labels "$labels"
  SESSION_CMDS=()
  if [[ -n "$cmds" ]]; then
    [[ ${#SESSION_LABELS[@]} -gt 0 ]] || error "--cmds requires --labels"
    parse_session_cmds "$cmds"
    (( ${#SESSION_CMDS[@]} == ${#SESSION_LABELS[@]} )) || error "--cmds count must match --labels count"
  fi

  # Always create a new detached session, separate from the caller's window.
  cmd_session_start_outside "$session_name"
}

cmd_attach() {
  local session_name="agent"
  local name_set=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        shift
        [[ $# -gt 0 ]] || error "--name requires a session name"
        $name_set && error "attach accepts only one session name"
        session_name="$1"
        name_set=true
        ;;
      -*)
        error "Unknown attach option: $1. Run 'agent-mux attach [--name <session>]'."
        ;;
      *)
        $name_set && error "attach accepts only one session name"
        session_name="$1"
        name_set=true
        ;;
    esac
    shift
  done

  [[ "$session_name" =~ ^[A-Za-z0-9._-]+$ ]] || error "invalid session name '$session_name'"
  require_tmux_binary
  tmux_cmd has-session -t "$session_name" 2>/dev/null || error "session not found: $session_name"

  if current_tmux_pane >/dev/null 2>&1; then
    tmux_cmd switch-client -t "$session_name"
  else
    tmux_cmd attach-session -t "$session_name"
  fi
}

cmd_session() {
  if [[ "${1:-}" == "help" || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    session_usage
    return
  fi

  if [[ $# -eq 0 ]]; then
    session_usage
    return
  fi

  if [[ "${1:-}" == --* ]]; then
    error "session options require an explicit subcommand. Run: agent-mux session start $*"
  fi

  local subcmd="$1"
  shift
  case "$subcmd" in
    start) cmd_session_start "$@" ;;
    list)  [[ $# -eq 0 ]] || error "session list does not accept arguments"; cmd_session_list ;;
    kill|close|rm|remove) cmd_session_kill "$@" ;;
    *) error "Unknown session subcommand: $subcmd. Run 'agent-mux session --help'." ;;
  esac
}

cmd_window_rename() {
  require_tmux_binary
  local name="" target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target|-t)
        shift
        [[ $# -gt 0 ]] || error "--target requires a window target"
        target="$1"
        ;;
      --help|-h)
        window_usage
        return
        ;;
      -*)
        error "Unknown window rename option: $1. Run 'agent-mux window --help'."
        ;;
      *)
        [[ -z "$name" ]] || error "window rename accepts only one window name"
        name="$1"
        ;;
    esac
    shift
  done

  [[ -n "$name" ]] || error "window rename requires <name>"
  [[ "$name" != *$'\n'* ]] || error "window name cannot contain newlines"

  if [[ -n "$target" ]]; then
    tmux_cmd rename-window -t "$target" "$name"
  else
    current_tmux_pane >/dev/null 2>&1 || error "window rename requires --target when outside tmux"
    tmux_cmd rename-window "$name"
  fi
  info "Renamed window to '$name'."
}

cmd_window() {
  if [[ "${1:-}" == "help" || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    window_usage
    return
  fi

  if [[ $# -eq 0 ]]; then
    window_usage
    return
  fi

  local subcmd="$1"
  shift
  case "$subcmd" in
    rename|name) cmd_window_rename "$@" ;;
    *) error "Unknown window subcommand: $subcmd. Run 'agent-mux window --help'." ;;
  esac
}

require_tmux_binary() {
  command -v tmux >/dev/null 2>&1 || error "tmux is not installed or not in PATH"
}

# --- Commands ---

install_skill() {
  local project_dir="$1"
  local source_url="${2:-$BASE_URL}"

  # Neutral path — readable by any non-Claude agent (Codex, Gemini, local models, etc.)
  # The Claude Code skill is installed user-wide (install_user_skill), so /agent-mux
  # works in every folder without a per-project copy.
  local neutral_dir="$project_dir/skills/agent-mux"
  info "Installing agent-mux skill to ${neutral_dir/#$HOME/\~}..."
  mkdir -p "$neutral_dir/references"
  download "$source_url/skills/agent-mux/SKILL.md"                    "$neutral_dir/SKILL.md"
  download "$source_url/skills/agent-mux/references/orchestration.md" "$neutral_dir/references/orchestration.md"
  download "$source_url/skills/agent-mux/references/tmux.md"          "$neutral_dir/references/tmux.md"
}

# User-wide Claude Code skill — enables /agent-mux in every project/folder.
install_user_skill() {
  local source_url="${1:-$BASE_URL}"
  info "Installing Claude Code skill to ${CLAUDE_USER_SKILL_DIR/#$HOME/\~}..."
  mkdir -p "$CLAUDE_USER_SKILL_DIR/references"
  download "$source_url/skills/agent-mux/SKILL.md"                    "$CLAUDE_USER_SKILL_DIR/SKILL.md"
  download "$source_url/skills/agent-mux/references/orchestration.md" "$CLAUDE_USER_SKILL_DIR/references/orchestration.md"
  download "$source_url/skills/agent-mux/references/tmux.md"          "$CLAUDE_USER_SKILL_DIR/references/tmux.md"
}

# Remove the user-wide skill only if it is ours (don't clobber a user's own
# same-named skill).
remove_user_skill() {
  [[ -d "$CLAUDE_USER_SKILL_DIR" ]] || return 0
  if [[ -f "$CLAUDE_USER_SKILL_DIR/SKILL.md" ]] && \
     grep -q '^name: agent-mux$' "$CLAUDE_USER_SKILL_DIR/SKILL.md" 2>/dev/null; then
    rm -rf "$CLAUDE_USER_SKILL_DIR"
    info "Removed ${CLAUDE_USER_SKILL_DIR/#$HOME/\~}"
  else
    info "Keeping user-managed ${CLAUDE_USER_SKILL_DIR/#$HOME/\~} (not installed by agent-mux)"
  fi
}

install_tmux_config() {
  local source_url="${1:-$BASE_URL}"
  warn "Your existing tmux config will be replaced with a symlink to ~/.agent-mux/tmux.conf"
  warn "Backups are stored in ~/.agent-mux/backups/"
  mkdir -p "$SMUX_DIR" "$BIN_DIR" "$BACKUP_DIR"
  backup_existing
  info "Downloading tmux.conf..."
  download "$source_url/.tmux.conf" "$SMUX_DIR/tmux.conf"
  mkdir -p "$TMUX_XDG_DIR"
  ln -sfn "$SMUX_DIR/tmux.conf" "$TMUX_XDG_DIR/tmux.conf"
  if tmux list-sessions &>/dev/null; then
    if tmux source-file "$SMUX_DIR/tmux.conf" 2>/dev/null; then
      info "Reloaded tmux config."
    fi
  fi
}

cmd_global_install() {
  local with_config=true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with-config|--config=true|--config=on|--config=yes|--config=1)
        with_config=true
        ;;
      --no-config|--without-config|--config=false|--config=off|--config=no|--config=0)
        with_config=false
        ;;
      *)
        error "Unknown install option: $1. Run 'agent-mux --help'."
        ;;
    esac
    shift
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

  # 3. Create directories and download binaries
  mkdir -p "$SMUX_DIR" "$BIN_DIR"

  # 4. Download tmux-agent
  info "Downloading tmux-agent..."
  download "$BASE_URL/scripts/tmux-agent" "$BIN_DIR/tmux-agent"
  chmod +x "$BIN_DIR/tmux-agent"

  # 5. Save agent-mux CLI (download to tmp then mv — avoids self-overwrite if running from PATH)
  info "Installing agent-mux CLI..."
  download "$BASE_URL/install.sh" "$BIN_DIR/agent-mux.tmp"
  mv "$BIN_DIR/agent-mux.tmp" "$BIN_DIR/agent-mux"
  chmod +x "$BIN_DIR/agent-mux"

  # 6. Install user-wide Claude Code skill (/agent-mux in every folder)
  install_user_skill "$BASE_URL"

  # 7. Install tmux config by default
  if [[ "$with_config" == true ]]; then
    install_tmux_config "$BASE_URL"
  fi

  # 8. Ensure PATH
  ensure_path

  echo ""
  printf '%b\n' "${GREEN}${BOLD}agent-mux installed!${NC}"
  echo ""
  echo "  tmux-agent:     ~/.agent-mux/bin/tmux-agent"
  echo "  agent-mux CLI:  ~/.agent-mux/bin/agent-mux"
  echo "  Claude skill:   ~/.claude/skills/agent-mux  (/agent-mux in every folder)"
  if [[ "$with_config" == true ]]; then
    echo "  Config:         ~/.agent-mux/tmux.conf"
  else
    echo "  Config:         skipped (--no-config)"
    warn "Alt controls and red pane borders require the agent-mux tmux config."
  fi
  echo ""
  echo "  In Claude Code (any folder): /agent-mux"
  echo "  For non-Claude agents in a repo: cd your-project && agent-mux install"
  echo "  Reference: agent-mux --help"
  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
    echo ""
    warn "Restart your shell or run: export PATH=\"\$HOME/.agent-mux/bin:\$PATH\""
  fi
}

cmd_install() {
  local with_config=true
  local project_dir="$PWD"
  local args=("$@")
  local i=0
  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      --with-config|--config=true|--config=on|--config=yes|--config=1)
        with_config=true
        ;;
      --no-config|--without-config|--config=false|--config=off|--config=no|--config=0)
        with_config=false
        ;;
      --project-dir)
        i=$(( i + 1 ))
        [[ $i -lt ${#args[@]} ]] || error "--project-dir requires a path"
        project_dir="${args[$i]}"
        ;;
      *)
        error "Unknown install option: ${args[$i]}. Run 'agent-mux --help'."
        ;;
    esac
    i=$(( i + 1 ))
  done

  info "Installing agent-mux neutral skill into ${project_dir/#$HOME/\~}..."

  # 1. Install the neutral skill for non-Claude agents in this repo.
  #    Claude's /agent-mux is user-wide (installed by curl|bash), not per-project.
  install_skill "$project_dir"

  # 2. Download and symlink tmux config by default
  if [[ "$with_config" == true ]]; then
    install_tmux_config "$BASE_URL"
  fi

  local neutral_rel="${project_dir/#$HOME/\~}/skills/agent-mux"
  echo ""
  printf '%b\n' "${GREEN}${BOLD}agent-mux neutral skill installed!${NC}"
  echo ""
  echo "  skill (neutral, non-Claude agents): $neutral_rel"
  if [[ "$with_config" == true ]]; then
    echo "  Config:                             ~/.agent-mux/tmux.conf"
  else
    echo ""
    echo "  Config:                             skipped (--no-config)"
    warn "Alt controls and red pane borders require the agent-mux tmux config."
  fi
  echo ""
  echo "  Claude Code: /agent-mux works in any folder (user-wide skill)."
}

cmd_update() {
  info "Updating agent-mux..."
  local updated_version="$VERSION"

  mkdir -p "$SMUX_DIR" "$BIN_DIR"

  info "Downloading tmux-agent..."
  download "$MAIN_URL/scripts/tmux-agent" "$BIN_DIR/tmux-agent"
  chmod +x "$BIN_DIR/tmux-agent"

  info "Updating agent-mux CLI..."
  download "$MAIN_URL/install.sh" "$BIN_DIR/agent-mux.tmp"
  updated_version=$(sed -n 's/^VERSION="\([^"]*\)".*/\1/p' "$BIN_DIR/agent-mux.tmp" | head -1)
  updated_version="${updated_version:-$VERSION}"
  mv "$BIN_DIR/agent-mux.tmp" "$BIN_DIR/agent-mux"
  chmod +x "$BIN_DIR/agent-mux"

  info "Updating user-wide Claude Code skill..."
  install_user_skill "$MAIN_URL"

  if [[ -d "$PWD/skills/agent-mux" ]]; then
    info "Updating agent-mux neutral skill..."
    install_skill "$PWD" "$MAIN_URL"
  fi

  # Only update tmux config if the active config is managed by agent-mux
  # (symlink exists AND points to our file, not a user-managed symlink).
  if [[ -L "$TMUX_XDG_DIR/tmux.conf" ]] && \
     [[ "$(readlink "$TMUX_XDG_DIR/tmux.conf")" == "$SMUX_DIR/tmux.conf" ]]; then
    mkdir -p "$BACKUP_DIR"
    backup_existing
    info "Downloading tmux.conf..."
    download "$MAIN_URL/.tmux.conf" "$SMUX_DIR/tmux.conf"
    if tmux list-sessions &>/dev/null; then
      if tmux source-file "$SMUX_DIR/tmux.conf" 2>/dev/null; then
        info "Reloaded tmux config."
      fi
    fi
  fi

  printf '%b\n' "${GREEN}${BOLD}agent-mux updated to v${updated_version}!${NC}"
}

cmd_uninstall() {
  info "Uninstalling agent-mux..."

  local can_restore_xdg=true

  # Remove only the symlink managed by agent-mux.
  if [[ -L "$TMUX_XDG_DIR/tmux.conf" ]] && \
     [[ "$(readlink "$TMUX_XDG_DIR/tmux.conf")" == "$SMUX_DIR/tmux.conf" ]]; then
    rm "$TMUX_XDG_DIR/tmux.conf"
    info "Removed symlink ~/.config/tmux/tmux.conf"
  elif [[ -e "$TMUX_XDG_DIR/tmux.conf" || -L "$TMUX_XDG_DIR/tmux.conf" ]]; then
    can_restore_xdg=false
    info "Keeping existing user-managed ~/.config/tmux/tmux.conf"
  fi

  local latest_symlink latest_xdg latest_legacy
  # shellcheck disable=SC2012  # ls -t is safe here: filenames have no spaces (timestamp format)
  latest_symlink=$(ls -t "$BACKUP_DIR"/tmux.conf.symlink.* 2>/dev/null | head -1 || true)
  # shellcheck disable=SC2012  # ls -t is safe here: filenames have no spaces (timestamp format)
  latest_xdg=$(ls -t "$BACKUP_DIR"/tmux.conf.[0-9]* 2>/dev/null | head -1 || true)
  # shellcheck disable=SC2012  # ls -t is safe here: filenames have no spaces (timestamp format)
  latest_legacy=$(ls -t "$BACKUP_DIR"/tmux.conf.legacy.* 2>/dev/null | head -1 || true)

  if [[ "$can_restore_xdg" == true ]]; then
    if [[ -n "$latest_symlink" ]]; then
      local target
      target=$(head -n 1 "$latest_symlink")
      if [[ -n "$target" ]]; then
        info "Restoring symlink backup: $latest_symlink"
        mkdir -p "$TMUX_XDG_DIR"
        ln -s "$target" "$TMUX_XDG_DIR/tmux.conf"
      fi
    elif [[ -n "$latest_xdg" ]]; then
      info "Restoring backup: $latest_xdg"
      mkdir -p "$TMUX_XDG_DIR"
      cp "$latest_xdg" "$TMUX_XDG_DIR/tmux.conf"
    fi
  fi

  if [[ -n "$latest_legacy" ]]; then
    info "Restoring legacy backup: $latest_legacy"
    cp "$latest_legacy" "$HOME/.tmux.conf"
  fi

  # Remove the user-wide Claude Code skill (only if it is ours)
  remove_user_skill

  # Remove agent-mux directory
  rm -rf "$SMUX_DIR"
  info "Removed ~/.agent-mux/"

  echo ""
  printf '%b\n' "${GREEN}${BOLD}agent-mux uninstalled.${NC}"
  echo ""
  echo "  Note: You may want to remove the PATH line from your shell rc file:"
  echo "    export PATH=\"\$HOME/.agent-mux/bin:\$PATH\""
}

cmd_version() {
  echo "agent-mux $VERSION"
}

cmd_keys() {
  cat <<'EOF'
Keyboard shortcuts (agent-mux tmux config)
Alt = Linux/WSL2 · Option = macOS · no prefix key

Pane    Alt+i/k/j/l   navigate up/down/left/right (no wrap)
Pane    Alt+n         new pane
Pane    Alt+w         close pane
Pane    Alt+o         cycle layouts
Pane    Alt+g         mark pane
Pane    Alt+y         swap with marked pane
Window  Alt+m         new window
Window  Alt+u         next window
Window  Alt+h         previous window
Scroll  Alt+Tab       toggle scroll mode
Scroll  i / k         scroll up / down
Scroll  I / K         half-page up / down
Scroll  q / Esc       exit scroll mode

Mouse   click=select pane · drag=copy to clipboard · wheel=scroll

Requires the agent-mux tmux config (installed by default).
EOF
}

cmd_cli_ref() {
  cat <<'EOF'
agent-mux — one-command tmux setup

Usage: agent-mux <command> [flags]

Commands:
  install [--no-config]              Install the neutral skill into the current project
    [--project-dir <path>]             Writes skills/agent-mux/ (current dir or --project-dir)
                                         for any non-Claude agent (Codex, Gemini, …).
                                         Claude's /agent-mux is user-wide (installed by
                                         curl|bash) and works in every folder already.
                                       Installs the agent-mux tmux config by default
                                       and symlinks it to ~/.config/tmux/tmux.conf.
                                       Your existing config is backed up to ~/.agent-mux/backups/.
                                       --no-config: keep your tmux config untouched.
                                       --with-config is accepted for compatibility.
  update                    Update tmux-agent, agent-mux CLI, and tmux.conf to latest
  session start             Create a new detached session (no auto-attach, never
                            splits the current window; errors if it exists)
    [--name <session>]        Default session name: agent
    [--labels a,b,c]          One pane per label; default: none (single pane)
    [--cmds x,y,z]            Optional command per pane; requires --labels
  session list              List tmux sessions
  session kill --name <s>   Kill a specific tmux session
  window rename <name>      Rename the current tmux window
    [--target <window>]       Required when outside tmux; example: agent:0
  attach [<session>]        Attach to a session by name (default: agent)
    [--name <session>]        Inside tmux: uses switch-client; outside: attach-session
  open [<session>]          Alias for attach; does not create sessions
  uninstall                 Remove agent-mux and restore previous tmux config (if backed up)
  keys                      Show keyboard shortcuts (agent-mux tmux config)
  version                   Print version
  --help, -h                Show this CLI reference

tmux-agent — cross-pane communication:
  tmux-agent list [--current]              Show panes (default: all sessions)
    [--session <name>]                       Filter panes to one session
  tmux-agent protocol                      Show minimal reply protocol (no tmux required)
  tmux-agent read <target> [lines]         Read last N lines from pane (default: 50)
  tmux-agent type <target> <text>          Type text into pane without pressing Enter
  tmux-agent send <target> <text>          Full cycle: read → type message → verify → Enter
  tmux-agent task <target> <text>          Send task with reply/protocol instructions
  tmux-agent message <target> <text>       Type text with sender header (no Enter; agent-to-agent)
  tmux-agent keys <target> <key>...        Send special keys (Enter, Escape, C-c, Tab, etc.)
  tmux-agent name <target> <label>         Label a pane (shown in tmux border)
  tmux-agent resolve <label>               Print pane target for a label
  tmux-agent id                            Print this pane's ID ($TMUX_PANE)
  tmux-agent doctor                        Diagnose tmux connectivity and socket issues

  tmux-agent send --file <target> <text>   Force file transport (auto when payload >2 KB)
  tmux-agent send --path <target> <file>   Send bytes from file (preserves newlines, binary)
  tmux-agent thread list [--limit N]       List recent threads
  tmux-agent thread read <id>              Read thread messages
    [--since-cursor] [--head N|--tail N|--bytes N]
  tmux-agent thread stat <id>              Show thread message count and size
  tmux-agent thread gc [--ttl <sec>]       Remove old threads (default TTL: 3600 s; --dry-run)

  tmux-agent pause [reason]                Block all cross-pane sends
  tmux-agent resume                        Unblock sends
  tmux-agent status                        Show paused/running state
  tmux-agent audit tail [n]                Show last N audit events (default: 20)
  tmux-agent audit stats                   Show send/thread/block counters

  Target: %N · session:window.pane · window-index · label set via 'tmux-agent name'
  Env:    TMUX_AGENT_SOCKET    override tmux server socket (skips auto-detection)
          TMUX_AGENT_THREAD_DIR override thread storage directory
          TMUX_AGENT_INLINE_THRESHOLD  max bytes before auto-spill to file (default: 2048)

Files:
  ~/.agent-mux/tmux.conf              tmux configuration (downloaded by default)
  ~/.agent-mux/bin/tmux-agent         cross-pane communication CLI
  ~/.agent-mux/bin/agent-mux          this CLI
  ~/.agent-mux/backups/               config backups
  ~/.claude/skills/agent-mux/         Claude Code skill — /agent-mux in every folder
  skills/agent-mux/                   per-project skill — neutral path (non-Claude agents)
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
    cmd_global_install "$@"
  fi
}

case "${1:-}" in
  "")                              _default_cmd "$@" ;;
  --with-config|--config=true|--config=on|--config=yes|--config=1|--no-config|--without-config|--config=false|--config=off|--config=no|--config=0)
                                  _default_cmd "$@" ;;
  install)                         cmd_install "${@:2}" ;;
  update)                          cmd_update ;;
  session)                         cmd_session "${@:2}" ;;
  window)                          cmd_window "${@:2}" ;;
  attach|open)                     cmd_attach "${@:2}" ;;
  uninstall|remove)                cmd_uninstall ;;
  keys|controls)                   cmd_keys ;;
  version|--version|-v|-V)         cmd_version ;;
  --help|-h)                       cmd_cli_ref ;;
  *)                               error "Unknown command: $1. Run 'agent-mux --help' for usage." ;;
esac
