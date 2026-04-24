#!/usr/bin/env bats
# Tests for tmux-agent thread commands (thread read, thread gc).
# These tests exercise filesystem operations only — no live tmux session required.

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  export XDG_RUNTIME_DIR="$BATS_TMPDIR/xdg-$$-$BATS_TEST_NUMBER"
  mkdir -p "$XDG_RUNTIME_DIR"
  export TMUX_PANE="%1"
  THREADS_DIR="${XDG_RUNTIME_DIR}/threads"

  # Helper: create a thread directory with manifest
  make_thread() {
    local id="$1"
    local tdir="${THREADS_DIR}/${id}"
    mkdir -p "${tdir}/messages" "${tdir}/cursors"
    printf '{"id":"%s","created":"2026-01-01T00:00:00Z"}\n' "$id" > "${tdir}/manifest.json"
    echo "$tdir"
  }
}

teardown() {
  rm -rf "$XDG_RUNTIME_DIR"
}

# ── thread read ──────────────────────────────────────────────────────────────

@test "thread read: returns all messages" {
  TDIR=$(make_thread "t-read-all")
  printf 'Hello from A' > "${TDIR}/messages/000001.md"
  printf 'Reply from B' > "${TDIR}/messages/000002.md"

  run bash "$TMUX_AGENT" thread read "t-read-all"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hello from A"* ]]
  [[ "$output" == *"Reply from B"* ]]
}

@test "thread read: creates cursor file after read" {
  TDIR=$(make_thread "t-cursor-create")
  printf 'msg1' > "${TDIR}/messages/000001.md"
  printf 'msg2' > "${TDIR}/messages/000002.md"

  bash "$TMUX_AGENT" thread read "t-cursor-create"

  CURSOR_FILE="${TDIR}/cursors/_1"
  [ -f "$CURSOR_FILE" ]
  CURSOR=$(cat "$CURSOR_FILE")
  [ "$CURSOR" = "000002" ]
}

@test "thread read: --since-cursor returns only new messages" {
  TDIR=$(make_thread "t-since-cursor")
  printf 'msg1' > "${TDIR}/messages/000001.md"
  printf 'msg2' > "${TDIR}/messages/000002.md"

  # First full read sets cursor to 000002
  bash "$TMUX_AGENT" thread read "t-since-cursor"

  # Add new message
  printf 'msg3 new' > "${TDIR}/messages/000003.md"

  run bash "$TMUX_AGENT" thread read "t-since-cursor" --since-cursor
  [ "$status" -eq 0 ]
  [[ "$output" == *"msg3 new"* ]]
  [[ "$output" != *"msg1"* ]]
  [[ "$output" != *"msg2"* ]]
}

@test "thread read: --since-cursor advances cursor" {
  TDIR=$(make_thread "t-cursor-advance")
  printf 'msg1' > "${TDIR}/messages/000001.md"
  bash "$TMUX_AGENT" thread read "t-cursor-advance"

  printf 'msg2' > "${TDIR}/messages/000002.md"
  bash "$TMUX_AGENT" thread read "t-cursor-advance" --since-cursor

  CURSOR=$(cat "${TDIR}/cursors/_1")
  [ "$CURSOR" = "000002" ]
}

@test "thread read: --since-cursor returns empty when no new messages" {
  TDIR=$(make_thread "t-no-new")
  printf 'msg1' > "${TDIR}/messages/000001.md"
  bash "$TMUX_AGENT" thread read "t-no-new"

  run bash "$TMUX_AGENT" thread read "t-no-new" --since-cursor
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "thread read: --since-cursor does not change cursor when no new messages" {
  TDIR=$(make_thread "t-cursor-stable")
  printf 'msg1' > "${TDIR}/messages/000001.md"
  bash "$TMUX_AGENT" thread read "t-cursor-stable"

  bash "$TMUX_AGENT" thread read "t-cursor-stable" --since-cursor

  CURSOR=$(cat "${TDIR}/cursors/_1")
  [ "$CURSOR" = "000001" ]
}

@test "thread read: fails with clear error on nonexistent thread" {
  run bash "$TMUX_AGENT" thread read "no-such-thread-xyz"
  [ "$status" -ne 0 ]
  [[ "$output" == *"thread not found"* ]]
}

@test "thread read: cursor update is atomic (tmp+mv, no .cur- files left)" {
  TDIR=$(make_thread "t-atomic-cursor")
  printf 'msg1' > "${TDIR}/messages/000001.md"
  bash "$TMUX_AGENT" thread read "t-atomic-cursor"

  # No temp files should remain
  TMP_COUNT=$(find "${TDIR}/cursors" -name '.cur-*' | wc -l)
  [ "$TMP_COUNT" -eq 0 ]
}

# ── thread gc ────────────────────────────────────────────────────────────────

@test "thread gc: exits cleanly when no threads directory exists" {
  rm -rf "${XDG_RUNTIME_DIR}/threads"
  run bash "$TMUX_AGENT" thread gc
  [ "$status" -eq 0 ]
  [[ "$output" == *"no threads"* ]]
}

@test "thread gc: removes thread older than TTL" {
  TDIR=$(make_thread "t-old")
  printf 'old msg' > "${TDIR}/messages/000001.md"

  # Age the thread's latest message
  touch -d "20 seconds ago" "${TDIR}/messages/000001.md" "${TDIR}"

  run bash "$TMUX_AGENT" thread gc --ttl 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed 1"* ]]
  [ ! -d "$TDIR" ]
}

@test "thread gc: preserves thread newer than TTL" {
  TDIR=$(make_thread "t-new")
  printf 'new msg' > "${TDIR}/messages/000001.md"

  run bash "$TMUX_AGENT" thread gc --ttl 9999
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed 0"* ]]
  [ -d "$TDIR" ]
}

@test "thread gc: breaks stale lock with dead PID" {
  TDIR=$(make_thread "t-stale-lock")
  printf 'msg' > "${TDIR}/messages/000001.md"
  mkdir -p "${TDIR}/.lock"
  printf '99999999' > "${TDIR}/.lock/pid"

  touch -d "60 seconds ago" "${TDIR}/.lock"

  run bash "$TMUX_AGENT" thread gc --ttl 9999
  [ "$status" -eq 0 ]
  [[ "$output" == *"broke 1"* ]]
  [ ! -d "${TDIR}/.lock" ]
}

@test "thread gc: preserves lock held by live process" {
  TDIR=$(make_thread "t-live-lock")
  printf 'msg' > "${TDIR}/messages/000001.md"
  mkdir -p "${TDIR}/.lock"
  printf '%d' "$$" > "${TDIR}/.lock/pid"

  touch -d "60 seconds ago" "${TDIR}/.lock"

  run bash "$TMUX_AGENT" thread gc --ttl 9999
  [ "$status" -eq 0 ]
  [[ "$output" == *"broke 0"* ]]
  [ -d "${TDIR}/.lock" ]
}

@test "thread gc: reports correct counts for mixed scenario" {
  make_thread "t-keep" > /dev/null
  printf 'new' > "${THREADS_DIR}/t-keep/messages/000001.md"

  make_thread "t-remove" > /dev/null
  printf 'old' > "${THREADS_DIR}/t-remove/messages/000001.md"
  touch -d "20 seconds ago" \
    "${THREADS_DIR}/t-remove/messages/000001.md" \
    "${THREADS_DIR}/t-remove"

  run bash "$TMUX_AGENT" thread gc --ttl 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed 1"* ]]
  [ -d "${THREADS_DIR}/t-keep" ]
  [ ! -d "${THREADS_DIR}/t-remove" ]
}

# ── thread subcommand errors ─────────────────────────────────────────────────

@test "thread: fails with no subcommand" {
  run bash "$TMUX_AGENT" thread
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires a subcommand"* ]]
}

@test "thread: fails with unknown subcommand" {
  run bash "$TMUX_AGENT" thread badcmd
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown thread subcommand"* ]]
}
