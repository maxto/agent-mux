# Multi-Agent Orchestration

agent-mux provides panes, labels, and message routing. It does not decide roles
or maintain shared memory. The planner/coordinator assigns roles for the current
task and integrates the results.

## Common Rules

- Use one planner/coordinator for decomposition and final integration.
- Give each agent a role, ownership boundary, forbidden files, task, expected
  reply format, and test/review duties.
- Avoid parallel edits to the same file. If two agents need the same file, one
  edits and the other reviews.
- QA, Security, and Adversarial agents are read-only by default.
- Use thread transport for long briefs, diffs, logs, and handoffs.

## Coding-Team Framework

```text
Planner / Architect
├── Front-end Agent
├── Back-end Agent
├── Data / DB Agent
├── DevOps Agent
├── QA Agent
├── Security Agent
└── Adversarial Agent
```

Example session:

```bash
agent-mux session start \
  --name app-dev \
  --labels planner,frontend,backend,data,devops,qa,security,adversarial
```

Example delegation:

```text
Role: Back-end Agent
Ownership: server code, API contracts, backend tests
Forbidden: UI files, deployment files unless asked
Task: implement the scheduler API changes
Expected reply: files changed, tests run, risks, next action
```

## Review Framework

Use this when planning or validating a design:

```text
Planner / Architect
├── Implementability Reviewer
├── Alternative Design Reviewer
└── Adversarial Reviewer
```

Send the same brief to reviewers with different focus areas. The planner
synthesizes the feedback and asks the human only for product or tradeoff
decisions.

## Company-Sim Framework

agent-mux is domain-agnostic. A non-coding workflow can use business roles:

```text
CEO / Chair
├── COO
├── CFO
├── CTO
├── CMO
├── Legal
└── Analyst
```

The same rules apply: one coordinator, explicit ownership, clear expected
output, and no hidden shared memory.

## Handoff Template

Use this shape for long handoffs:

```markdown
# agent-mux Handoff

from:
to:
role:
status: done | blocked | needs_review | needs_context | failed

## Goal
## Ownership
## Changes Made
## Tests Run
## Findings
## Risks
## Next Action Requested
```

Send it with:

```bash
tmux-agent send --path qa handoff.md
```
