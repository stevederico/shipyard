# Gap Analysis: Shipyard vs Ramp Inspect vs Stripe Minions

## What Shipyard already has that they have

| Capability | Ramp | Stripe | Shipyard |
|---|---|---|---|
| Task queue | Slack, web, Chrome ext, voice | Slack, tickets, CLI | todos.md |
| Branch isolation | Per-sandbox branches | Devbox branches | `factory/` branches |
| Autonomous coding | OpenCode in sandbox | Goose fork | Claude Code `-p` |
| PR creation | GitHub API via user token | GitHub | `gh pr create` |
| Deterministic + agentic stages | Yes | Blueprints | 12-stage pipeline |
| Coding standards enforcement | MCP plugins + skill files | Scoped rule files per directory | Factory prompt + project CLAUDE.md |
| Test execution | Full-stack in sandbox | Selective CI + local lints | `deno run test` |
| Logging | Dashboard + metrics | Unknown | Timestamped logs |

## Gaps — things they have that Shipyard doesn't

| Gap | Ramp | Stripe | Impact | Effort |
|---|---|---|---|---|
| **Self-verification** | Screenshots before/after, Sentry errors, Datadog metrics, LaunchDarkly flags | Local lint daemon (<5s), selective CI, autofix | **High** — Shipyard ships without visual or runtime verification | Medium — add `/qa` skill call post-ship |
| **CI iteration loop** | Runs tests in sandbox, agent fixes | Max 2 CI rounds, first with autofix, second agent attempt | **High** — Shipyard's stage 9 FIX is stubbed | Medium — implement the retry loop |
| **Parallel sessions** | Hundreds concurrent on Modal, child sessions across repos | Parallel devboxes on EC2 | **Medium** — Shipyard runs 1 task at a time | Low — run multiple `factory.sh` in tmux panes with worktrees |
| **Environment isolation** | Full sandbox: Postgres, Redis, Temporal, RabbitMQ, Chromium | Pre-warmed EC2 devboxes, isolated from prod | **Medium** — Shipyard runs on your local machine, shares state | High — would need Docker or Modal |
| **Visual verification** | Chromium screenshots, before/after diffs on PRs | Not mentioned | **Medium** — Shipyard has no visual check | Low — you already have `/qa` and `agent-browser` |
| **Warm startup** | Snapshots every 30 min, <5s startup | Devboxes in 10s with warm caches | **Low** — Shipyard's `git pull` is fast enough for solo use | N/A |
| **Multi-repo context** | Child sessions spawn to read other repos | Toolshed provides cross-repo context | **Low** — your projects are independent | Low — could add context from related repos |
| **Curated tool subsets** | MCPs + custom plugins | ~500 MCP tools in Toolshed, curated per agent | **Low** — Claude Code already has your skills/agents | N/A |
| **Multiple trigger sources** | Slack, web, Chrome ext, voice, PR comments | Slack, tickets, CLI | **Low** — todos.md is fine for solo | Low — could add GitHub issue trigger |
| **Metrics dashboard** | Merged PR rate, live user count | PRs/week | **Low** — logs are sufficient for solo | Low — could count PRs in git log |
| **Non-engineer access** | Chrome extension for PMs/designers | N/A | **None** — you're a solo developer | N/A |

## Top 3 actionable gaps

### 1. Self-verification (post-ship QA)

Ramp runs Chromium screenshots and checks Sentry after every PR. Shipyard already has access to `/qa` and `agent-browser`. Add a stage between SHIP and UPDATE that deploys to a preview URL and runs a visual check.

### 2. CI iteration loop (stage 9 FIX)

Stripe caps at 2 CI rounds: first with autofix, second with agent attempt. Shipyard's stage 9 is stubbed. Implement: if lint/tests fail, pass failures back to Claude, re-run tests, max 3 attempts.

### 3. Parallel sessions

Ramp runs hundreds concurrent. Shipyard could run 3-5 factory instances in tmux panes, each on a different task, using `git worktree` for isolation. No cloud infra needed.

## What Shipyard has that they don't

- **Global todo.md as single source of truth** — simpler than Slack/ticket triggers for a solo developer
- **Per-project todo.md with subtask tracking** — automatic project-level context, not just a prompt
- **Completion percentage `[N]`** — visibility into how close projects are to done
- **Zero infrastructure** — no VMs, no Docker, no cloud. Just a shell script.

## Sources

- [Why We Built Our Own Background Agent — Ramp Builders](https://builders.ramp.com/post/why-we-built-our-background-agent)
- [How Ramp built a full context background coding agent on Modal](https://modal.com/blog/how-ramp-built-a-full-context-background-coding-agent-on-modal)
- [Minions Part 1 — Stripe](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents)
- [Minions Part 2 — Stripe](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents-part-2)
