# Live Thread Transport Benchmark

Use this benchmark to compare:

- inline paste into an agent prompt
- file-backed thread transport (`tmux-agent send --file`)

The goal is to measure how many characters actually enter the receiver's prompt
for the same payload, then project savings across repeated turns.

## What This Benchmark Measures

For each case, the receiver reports:

1. transport method received: `inline` or `file`
2. exact character count of the raw message line seen in the prompt

This measures prompt growth directly. It does not estimate tokens.

## Invalid Setups To Avoid

- Do not send to a plain `bash` pane and infer prompt cost from shell output.
- Do not compare different payload sizes.
- Do not rely on `tmux-agent send` for large inline payloads: it auto-spills to
  file transport above 2KB.
- Do not mix character counts with token estimates in the same conclusion.

## Roles

- Master: receiver and measurer
- Slave: sender

In the repo's default tmux layout, a typical setup is:

- `claude` = slave sender
- `codex` = master receiver

## Payload Rules

- Use a single-line ASCII payload.
- Reuse the exact same payload for both cases.
- Recommended size for a large-payload benchmark: `12288` chars.

Example payload generator:

```bash
PAYLOAD=$(python3 - <<'PY'
s = ('ABCD1234' * 2000)[:12288]
print('BENCH12K:' + s, end='')
PY
)
```

## Case 1: True Inline Large Payload

Do not use `tmux-agent send` here, because it will auto-spill above 2KB.
Use the manual read/message/read/keys cycle instead.

Run from the slave pane:

```bash
~/.agent-mux/bin/tmux-agent read codex
~/.agent-mux/bin/tmux-agent message codex "CASE=INLINE-12K $PAYLOAD"
~/.agent-mux/bin/tmux-agent read codex
~/.agent-mux/bin/tmux-agent keys codex Enter
```

The master records the exact character count of the raw received line.

## Case 2: File Transport Ping

Run from the slave pane:

```bash
~/.agent-mux/bin/tmux-agent send --file codex "CASE=FILE-12K $PAYLOAD"
```

The master records the exact character count of the ping line seen in the
prompt. The thread payload on disk is not counted for prompt growth.

## Master Output Format

For each received case, reply with:

```text
1) <method>
2) <chars> chars
```

Example:

```text
1) inline
2) 12394 chars
```

## Savings Calculation

Single-turn prompt savings:

```text
savings_pct = (inline_chars - file_ping_chars) / inline_chars * 100
```

Multi-turn prompt growth for `N` repeated turns:

```text
inline_total = inline_chars * N
file_total = file_ping_chars * N
delta = inline_total - file_total
```

## Recommended Report

Report these numbers:

- payload size sent
- inline chars seen in prompt
- file ping chars seen in prompt
- single-turn savings percentage
- projected totals for 5 and 10 turns

## Notes

- If the receiver later runs `tmux-agent thread read`, that read intentionally
  brings payload content into the receiver context. Count that separately.
- This benchmark measures the savings of the transport itself, not downstream
  choices by the receiving agent.
