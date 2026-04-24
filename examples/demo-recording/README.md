# agent-mux demo recording

Deterministic demo: no real agents, no API keys, no live models.

Shows: 3-pane session (coordinator / codex / gemini), cross-pane messaging via `tmux-agent`, and thread transport for large payloads.

## Run the demo

```bash
# Script-output mode: prints step-by-step to stdout (no tmux UI)
bash examples/demo-recording/demo.sh

# Visual mode: attaches to the live 3-pane tmux session
bash examples/demo-recording/demo.sh --attach
```

## Record

```bash
# Requires: asciinema (records the full 3-pane tmux layout via --attach)
bash examples/demo-recording/record.sh
```

Output: `examples/demo-recording/assets/demo.cast`

To convert to GIF:

```bash
# Requires: agg (https://github.com/asciinema/agg)
agg examples/demo-recording/assets/demo.cast examples/demo-recording/assets/demo.gif
```

## What the demo shows

1. **Discover panes** — `tmux-agent list` shows all labeled panes
2. **Cross-pane messaging** — coordinator sends to codex and gemini without copy-paste
3. **Thread transport** — large payload (~9KB diff) sent with `send --file`; receiver gets only a ~114-char ping; full content stays on disk until `thread read`

## Requirements

- tmux 3.2+
- `tmux-agent` installed (`curl -fsSL https://maxto.github.io/agent-mux/install.sh | bash`)
- python3 (generates the mock large payload)
- asciinema — recording only
- agg — GIF export only

## Files

| File | Description |
|---|---|
| `demo.sh` | Creates session, drives panes. Default: script output. `--attach`: types into coordinator pane and attaches for visual recording |
| `record.sh` | Runs `demo.sh --attach` under asciinema; optionally generates GIF with agg |
| `assets/` | Output directory for `demo.cast` and `demo.gif` (not committed to git) |
