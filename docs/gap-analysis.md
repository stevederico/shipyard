# Gap Analysis: Shipyard vs Ramp Inspect vs Stripe Minions

Ramp and Stripe are running factories at enterprise scale — hundreds of concurrent sandboxed VMs,
integrated into Slack/Sentry/Datadog, shipping 30-50% of their merged PRs autonomously. Shipyard
is a single shell script on your laptop doing the same core loop: task in, code, test, PR out.

As of v0.22, most of the high-impact gaps have been closed.

---

## At parity

| Capability | Ramp | Stripe | Shipyard |
|---|---|---|---|
| Task queue | Slack, web, Chrome ext, voice | Slack, tickets, CLI | `tasks/` markdown files + `--issues` GitHub sync |
| Branch isolation | Per-sandbox branches | Devbox branches | Worktree-isolated `shipyard/` branches |
| Autonomous coding | OpenCode in sandbox | Goose fork | Claude Code `-p` |
| PR creation | GitHub API via user token | GitHub | `gh pr create` |
| Deterministic + agentic stages | Yes | Blueprints | Multi-stage pipeline (PICK, ROUTE, PULL, BRANCH, CODE, LINT, FIX, SHIP, VERIFY, UPDATE) |
| Coding standards | MCP plugins + skill files | Scoped rule files per directory | `standards.md` + project `CLAUDE.md` |
| Self-verification | Chromium screenshots, Sentry, Datadog | Local lint daemon, selective CI, autofix | VERIFY stage: dev server + agent-browser + verify/fix loop |
| CI iteration loop | Tests in sandbox, agent fixes | Max 2 CI rounds with autofix | FIX stage: lint failures to Claude, max 2 attempts |
| Parallel sessions | Hundreds concurrent on Modal | Parallel devboxes on EC2 | `--parallel N` with atomic task locks + worktrees |
| Visual verification | Chromium screenshots, before/after diffs on PRs | Not mentioned | Screenshots committed to branch + attached to PR comments |

---

## Remaining gaps

| Gap | Impact | Effort |
|---|---|---|
| Environment isolation | Medium | High |
| Post-deploy observability | Low (solo) / High (team) | Medium |
| Intake breadth | Low (solo) | Medium |

**Environment isolation.** Ramp spins up full sandboxes on Modal (Postgres, Redis, Chromium).
Stripe uses pre-warmed EC2 instances that provision in 10 seconds. Shipyard runs on your Mac and
shares local state. Worktrees handle code isolation and most projects use SQLite, so this is less
painful than it sounds. Closing it would require Docker or Modal per run — not justified for solo
use yet.

**Post-deploy observability.** Ramp queries Sentry and Datadog after shipping. Shipyard verifies
against the dev server but doesn't watch production post-merge. Next step: a post-deploy health
check that curls the production URL and checks for 200s.

**Intake breadth.** Ramp has a Chrome extension where PMs visually select UI elements. Stripe
triggers from Slack messages. Shipyard triggers from markdown files and GitHub issues — ideal for
solo, but a team would want Slack or web intake.

---

## Where Shipyard is ahead

**Zero infrastructure.** Ramp needs Modal. Stripe needs EC2 devboxes. You need `bash factory.sh`.
One file, no dependencies, runs on a laptop.

**Self-healing verify loop.** Most enterprise agents run verification as a pass/fail gate. Shipyard's
VERIFY stage detects failures and triggers a fix session automatically — verify, catch issues, fix,
re-verify — before marking the task done.

**GitHub issue intake.** `--issues owner/repo` pulls labeled issues into the task queue. When the
factory ships a PR, it comments the PR link on the issue and closes it. Two-way integration without
webhooks.

---

## Ramp Inspect

Cloud-based agent on **Modal**. Uses **OpenCode** as the coding engine. Wired into Sentry, Datadog,
LaunchDarkly, GitHub, Buildkite, Slack — verifies its own work. ~50% of Ramp's merged PRs are now
agent-initiated (up from 30%). Over 80% of Inspect's own code is written by Inspect. Chrome extension
for PMs/designers. Open-sourced the blueprint; community implementation at
[ColeMurray/background-agents](https://github.com/ColeMurray/background-agents).

- [Why We Built Our Own Background Agent](https://builders.ramp.com/post/why-we-built-our-background-agent)
- [How Ramp built a full context background coding agent on Modal](https://modal.com/blog/how-ramp-built-a-full-context-background-coding-agent-on-modal)

## Stripe Minions

Internal fork of **Goose** (Block's open-source agent). **1,300+ PRs/week**, all zero human-written
code, all human-reviewed. Architecture uses "blueprints" — state machines interleaving deterministic
and agentic nodes. ~500 curated MCP tools via "Toolshed." Run in pre-loaded EC2 devboxes.

- [Minions Part 1](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents)
- [Minions Part 2](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents-part-2)

---

## The "Dark Factory" pattern

"Code factory is one prompt, fully tested, no human" — the **dark factory** concept from lights-out
manufacturing. Fully autonomous coding pipeline: spec in, tested code out, zero human writing or
review. BCG Platinion published a formal framework. StrongDM (3-person team) ships production
Rust/Go this way. The pattern has gone from novelty to documented practice.

- [BCG Dark Software Factory](https://www.bcgplatinion.com/insights/the-dark-software-factory)
- [Dark Factory pattern (HackerNoon)](https://hackernoon.com/the-dark-factory-pattern-moving-from-ai-assisted-to-fully-autonomous-coding)
