# Gap Analysis: Shipyard vs Ramp Inspect vs Stripe Minions

Ramp and Stripe are running factories at enterprise scale — hundreds of concurrent sandboxed VMs, integrated
into Slack/Sentry/Datadog, shipping 30-50% of their merged PRs autonomously. Shipyard is a single shell script
on your laptop doing the same core loop: task in, code, test, PR out.

As of v0.21+, most of the high-impact gaps have been closed.

---

## At parity

| Capability | Ramp | Stripe | Shipyard |
|---|---|---|---|
| Task queue | Slack, web, Chrome ext, voice | Slack, tickets, CLI | `tasks/` markdown files + `--issues` GitHub sync |
| Branch isolation | Per-sandbox branches | Devbox branches | Worktree-isolated `shipyard/` branches |
| Autonomous coding | OpenCode in sandbox | Goose fork | Claude Code `-p` |
| PR creation | GitHub API via user token | GitHub | `gh pr create` |
| Deterministic + agentic stages | Yes | Blueprints | 12-stage pipeline (PICK, ROUTE, PULL, BRANCH, CODE, LINT, FIX, SHIP, VERIFY, UPDATE) |
| Coding standards | MCP plugins + skill files | Scoped rule files per directory | `standards.md` + project `CLAUDE.md` |
| Test execution | Full-stack in sandbox | Selective CI + local lints | `deno run test` |
| Self-verification | Chromium screenshots, Sentry, Datadog | Local lint daemon, selective CI, autofix | VERIFY stage: dev server + agent-browser screenshots + verify/fix loop |
| CI iteration loop | Tests in sandbox, agent fixes | Max 2 CI rounds with autofix | FIX stage: lint failures to Claude, re-run, max 2 attempts |
| Parallel sessions | Hundreds concurrent on Modal | Parallel devboxes on EC2 | `--parallel N` with atomic task locks + worktrees |
| Visual verification | Chromium screenshots, before/after diffs on PRs | Not mentioned | Screenshots committed to branch + attached to PR comments |

**Pipeline structure.** Stripe calls theirs "blueprints" — state machines that mix deterministic nodes (git, lint)
with agentic nodes (LLM reasoning). Shipyard's pipeline is exactly this pattern. Deterministic stages
(PICK, ROUTE, PULL, BRANCH, LINT, SHIP, UPDATE) interleave with agentic stages (CODE, FIX, VERIFY). Same
architecture, different scale.

**Task intake.** Shipyard has markdown files in `tasks/` plus `--issues` to pull labeled GitHub issues into
the queue automatically. For a solo developer, a text file you control is arguably better — no infrastructure,
no permissions, no webhook setup.

**Self-verification.** Shipyard now has a full VERIFY stage: starts a dev server, runs agent-browser to snapshot
the DOM and take screenshots, compares implementation against task requirements, and triggers a fix session if
verification fails. Screenshots are committed to the branch and attached to the PR as comments. The `--verify`
flag also lets you batch-verify all open PRs for a repo.

**CI iteration loop.** If LINT finds issues (secrets committed, missing changelog, version not bumped, test
failures), FIX passes them to a Claude session, re-runs lint, and caps at 2 attempts. Same pattern as Stripe.

**Parallel execution.** `--parallel N` agents, each pulling a different task via atomic lock files (mkdir-based),
coding in isolated git worktrees with agent-labeled output. 3-5 instances burns through a task queue fast on a
single machine.

---

## Remaining gaps

| Gap | Impact | Effort | Notes |
|---|---|---|---|
| Environment isolation | Medium | High | Would need Docker/Modal per run. Worktrees + SQLite cover most cases |
| Observability integration | Low (solo) / High (team) | Medium | No post-deploy Sentry/Datadog checks |
| Intake breadth | Low (solo) | Medium | No Chrome extension or Slack trigger for non-engineers |

**Gap 1: Environment isolation (MEDIUM impact, HIGH effort)**

Ramp spins up a full sandbox per session: Postgres, Redis, Temporal, RabbitMQ, Chromium, VS Code server. Stripe
uses pre-warmed EC2 instances that provision in 10 seconds.

Shipyard runs on your Mac. It shares your local state — if a factory run messes up a database or leaves ports
occupied, it affects your next run. Worktrees handle code isolation, and most projects use SQLite (file-based,
no shared server), so this is less painful than it sounds. Closing this would require Docker containers or Modal
sandboxes per factory run. The effort-to-value ratio doesn't justify it yet for a solo developer.

**Gap 2: Observability integration (LOW impact for solo, HIGH for teams)**

Ramp queries Sentry for new errors and Datadog for metric regressions after shipping. Shipyard checks the dev
server and takes screenshots but doesn't watch production metrics post-merge. For a solo developer who monitors
their own deploys, this matters less. The next high-value addition would be a post-deploy health check — after
the PR merges and deploys, curl the production URL and check for 200s.

**Gap 3: Intake breadth (LOW impact for solo)**

Ramp has a Chrome extension where PMs visually select UI elements and request changes. Stripe triggers from Slack.
Shipyard triggers from markdown files and GitHub issues. For a solo developer, markdown files are the ideal
interface. For a team, Slack or web intake would lower the bar for non-engineers to submit tasks.

---

## Where Shipyard is ahead

**Per-project todo.md.** Neither Ramp nor Stripe has publicly described anything like this. Their agents get a
single prompt or ticket. Shipyard reads the project's own todo file for subtask context, picks the first
incomplete item, marks it done, and only marks the global task done when all subtasks are complete.

**Zero infrastructure.** Ramp needs Modal. Stripe needs EC2 devboxes. You need `bash factory.sh`. One file,
no dependencies, runs on a laptop.

**Self-healing verify loop.** Most enterprise agents run verification as a pass/fail gate. Shipyard's VERIFY
stage detects failures and triggers a fix session automatically — verify, catch issues, fix, re-verify — before
marking the task done.

**GitHub issue intake.** `--issues owner/repo` pulls labeled issues into the task queue, and when the factory
ships a PR, it comments the PR link on the issue and closes it. Lightweight two-way integration without webhooks.

---

## The Big Company Agents

### Ramp Inspect
Cloud-based autonomous coding agent. Each session spins up a sandboxed VM on **Modal** with full-stack infra (Postgres, Redis, etc). Uses **OpenCode** as the coding engine. Key differentiator: it's wired into Sentry, Datadog, LaunchDarkly, GitHub, Buildkite, Slack — so it verifies its own work. Responsible for 30%+ of Ramp's merged PRs. Has a Chrome extension so PMs/designers can visually select UI elements and request changes. Ramp open-sourced the blueprint; community implementation at [ColeMurray/background-agents](https://github.com/ColeMurray/background-agents).

- [Why We Built Our Own Background Agent - Ramp Builders](https://builders.ramp.com/post/why-we-built-our-background-agent)
- [How Ramp built a full context background coding agent on Modal](https://modal.com/blog/how-ramp-built-a-full-context-background-coding-agent-on-modal)

### Stripe Minions
Built on an internal fork of **Goose** (Block's open-source agent). Merging **1,300+ PRs/week**. Triggered primarily via Slack. Architecture uses "blueprints" — state machines that interleave deterministic nodes (git, lint, format) with agentic nodes (LLM reasoning). Run in "devboxes" (pre-loaded EC2 instances). Has ~500 curated internal MCP tools via "Toolshed." Key insight: success depends more on engineering fundamentals (test infra, dev environments) than model choice.

- [Minions Part 1](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents)
- [Minions Part 2](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents-part-2)

---

## The "Code Factory" / "Dark Factory" Pattern

"Code factory is one prompt, fully tested, no human" — this is the **dark factory** concept from lights-out manufacturing. Fully autonomous AI coding pipeline: spec in, tested code out, zero human writing or review. StrongDM (3-person team) ships production Rust/Go this way. Cursor reports 35% of internal PRs are agent-created. It's a distinct level beyond "AI-assisted."
