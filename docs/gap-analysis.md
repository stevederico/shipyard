# Gap Analysis: Shipyard vs The Field

Autonomous coding agents went mainstream in 2025. Every major platform shipped one: OpenAI Codex,
GitHub Copilot coding agent, Cursor Background Agents, plus internal systems at Ramp, Stripe,
Google, Pinterest, DoorDash, Spotify. The pattern is the same everywhere — spec in, code, test,
PR out — just at different scales.

Shipyard is a single shell script on your laptop doing the same core loop. As of v0.22, most of
the high-impact gaps with enterprise systems have been closed.

---

## At parity

| Capability | Enterprise agents | Shipyard |
|---|---|---|
| Task queue | Slack, web, Chrome ext, GitHub issues | `tasks/` markdown files + `--issues` GitHub sync |
| Branch isolation | Sandboxed VMs, devboxes | Worktree-isolated `shipyard/` branches |
| Autonomous coding | OpenCode, Goose, Codex, Copilot | Claude Code `-p` |
| PR creation | GitHub API | `gh pr create` |
| Deterministic + agentic stages | Blueprints, state machines | Multi-stage pipeline (PICK, ROUTE, PULL, BRANCH, CODE, LINT, FIX, SHIP, VERIFY, UPDATE) |
| Coding standards | MCP plugins, scoped rules | `standards.md` + project `CLAUDE.md` |
| Self-verification | Chromium screenshots, Sentry, Datadog | VERIFY stage: dev server + agent-browser + verify/fix loop |
| CI iteration loop | Max 2 rounds with autofix | FIX stage: lint failures to Claude, max 2 attempts |
| Parallel sessions | Hundreds of VMs | `--parallel N` with atomic task locks + worktrees |
| Visual verification | Before/after screenshots on PRs | Screenshots committed to branch + attached to PR comments |

---

## Remaining gaps

| Gap | Impact | Effort |
|---|---|---|
| Environment isolation | Medium | High |
| Post-deploy observability | Low (solo) / High (team) | Medium |
| Intake breadth | Low (solo) | Medium |

**Environment isolation.** Ramp spins up full sandboxes on Modal (Postgres, Redis, Chromium).
OpenAI Codex and Cursor run isolated VMs. Shipyard runs on your Mac and shares local state.
Worktrees handle code isolation and most projects use SQLite, so this is less painful than it
sounds. Closing it would require Docker or Modal per run — not justified for solo use yet.

**Post-deploy observability.** Ramp queries Sentry and Datadog after shipping. Shipyard verifies
against the dev server but doesn't watch production post-merge. Next step: a post-deploy health
check that curls the production URL and checks for 200s.

**Intake breadth.** Ramp has a Chrome extension where PMs visually select UI elements. Spotify's
internal "Honk" triggers from Slack. Shipyard triggers from markdown files and GitHub issues —
ideal for solo, but a team would want Slack or web intake.

---

## Where Shipyard is ahead

**Zero infrastructure.** Ramp needs Modal. Stripe needs EC2 devboxes. OpenAI Codex needs cloud
VMs. You need `bash factory.sh`. One file, no dependencies, runs on a laptop.

**Self-healing verify loop.** Most enterprise agents run verification as a pass/fail gate. Shipyard's
VERIFY stage detects failures and triggers a fix session automatically — verify, catch issues, fix,
re-verify — before marking the task done.

**GitHub issue intake.** `--issues owner/repo` pulls labeled issues into the task queue. When the
factory ships a PR, it comments the PR link on the issue and closes it. Two-way integration without
webhooks.

---

## The Field

### Ramp Inspect
Cloud-based agent on **Modal**. Uses **OpenCode** as the coding engine. Wired into Sentry, Datadog,
LaunchDarkly, GitHub, Buildkite, Slack — verifies its own work. ~50% of Ramp's merged PRs are now
agent-initiated (up from 30%). Over 80% of Inspect's own code is written by Inspect. Chrome extension
for PMs/designers. Open-sourced the blueprint; community implementation at
[ColeMurray/background-agents](https://github.com/ColeMurray/background-agents).

- [Why We Built Our Own Background Agent](https://builders.ramp.com/post/why-we-built-our-background-agent)
- [How Ramp built a full context background coding agent on Modal](https://modal.com/blog/how-ramp-built-a-full-context-background-coding-agent-on-modal)

### Stripe Minions
Internal fork of **Goose** (Block's open-source agent). **1,300+ PRs/week**, all zero human-written
code, all human-reviewed. Architecture uses "blueprints" — state machines interleaving deterministic
and agentic nodes. ~500 curated MCP tools via "Toolshed." Run in pre-loaded EC2 devboxes.

- [Minions Part 1](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents)
- [Minions Part 2](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents-part-2)

### OpenAI Codex
Cloud-based coding agent available in ChatGPT, as a standalone web app, a CLI tool, and a GitHub
integration (`@codex` on PRs and issues). Runs tasks in parallel sandboxes. Currently powered by
GPT-5.4. Included with ChatGPT Plus, Pro, Business, Edu, and Enterprise plans.

- [Introducing the Codex app](https://openai.com/index/introducing-the-codex-app/)
- [openai/codex CLI](https://github.com/openai/codex)

### GitHub Copilot Coding Agent
Assign a GitHub issue to Copilot. It boots a VM, clones the repo, codes autonomously, pushes commits
to a draft PR. Available to all paid Copilot subscribers. GA September 2025.

- [GitHub Copilot coding agent](https://github.blog/news-insights/product-news/github-copilot-meet-the-new-coding-agent/)

### Cursor Background Agents
Up to 8 parallel agents using git worktrees, running in isolated Ubuntu VMs. "Automations" trigger
agents from Slack messages, codebase changes, or timers. 35% of Cursor's own merged PRs are
agent-generated.

- [Cursor 2.0](https://cursor.com/changelog/2-0)

### Factory AI (Droids)
Full SDLC agents. Ranked #1 on Terminal-Bench (58.8%). Customers include MongoDB, EY, Zapier, Bayer.
Raised $50M. 200% QoQ growth.

- [Factory Droids launch](https://siliconangle.com/2025/09/25/factory-unleashes-droids-software-agents-50m-fresh-funding/)

### Devin 2.0
Price dropped from $500/mo to $20/mo. PR merge rate improved from 34% to 67%. Goldman Sachs piloting
alongside 12,000 engineers.

- [Devin 2025 performance review](https://cognition.ai/blog/devin-annual-performance-review-2025)

---

## Industry stats

| Company | Metric |
|---|---|
| Google | ~50% of code written by AI agents |
| Pinterest | ~50% of new code is AI-generated |
| DoorDash | 90%+ daily AI usage across all engineers |
| Stripe | 1,300 agent PRs/week |
| Ramp | ~50% of merged PRs agent-initiated |
| Cursor | 35% of internal PRs are agent-generated |
| Industry avg (DX, 135K devs) | 22% of merged code is AI-authored |

Fully autonomous agents are involved in <0.2% of PRs at most companies. Adoption is top-heavy —
a handful of companies drive the numbers.

---

## The "Dark Factory" pattern

"Code factory is one prompt, fully tested, no human" — the **dark factory** concept from lights-out
manufacturing. Fully autonomous coding pipeline: spec in, tested code out, zero human writing or
review. BCG Platinion published a formal framework. StrongDM (3-person team) ships production
Rust/Go this way. Spotify's internal "Honk" lets engineers trigger autonomous changes via Slack
from their phones. The pattern has gone from novelty to documented practice.

- [BCG Dark Software Factory](https://www.bcgplatinion.com/insights/the-dark-software-factory)
- [Dark Factory pattern (HackerNoon)](https://hackernoon.com/the-dark-factory-pattern-moving-from-ai-assisted-to-fully-autonomous-coding)
