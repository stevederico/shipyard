The big picture

  Ramp and Stripe are running factories at enterprise scale — hundreds of concurrent sandboxed VMs, integrated
  into Slack/Sentry/Datadog, shipping 30-50% of their merged PRs autonomously. Shipyard is a single shell script
  on your laptop doing the same core loop: task in, code, test, PR out.

  As of v0.21+, most of the high-impact gaps have been closed.

  ---
  Where you're at parity

  Pipeline structure. Stripe calls theirs "blueprints" — state machines that mix deterministic nodes (git, lint)
  with agentic nodes (LLM reasoning). Shipyard's 12-stage pipeline is exactly this pattern. Deterministic stages
  (PICK, ROUTE, PULL, BRANCH, LINT, SHIP, UPDATE) interleave with agentic stages (CODE, FIX, VERIFY). Same
  architecture, different scale.

  Task intake. Ramp has Slack, web, Chrome extension, voice. Stripe has Slack and tickets. Shipyard has markdown
  files in tasks/ plus --issues to pull labeled GitHub issues into the queue automatically. For a solo developer,
  a text file you control is arguably better — no infrastructure, no permissions, no webhook setup.

  Branch isolation and PR creation. Everyone creates a feature branch, codes on it, opens a PR. No difference.

  Coding standards enforcement. Stripe uses scoped rule files per directory. Ramp uses MCP plugins. Shipyard
  uses CLAUDE.md per project plus standards.md injected into every factory session. Same concept.

  Self-verification. Ramp takes before/after screenshots with Chromium, checks Sentry, queries Datadog. Shipyard
  now has a full VERIFY stage: starts a dev server, runs agent-browser to snapshot the DOM and take screenshots,
  compares implementation against task requirements, and triggers a fix session if verification fails. Screenshots
  are committed to the branch and attached to the PR as comments. The --verify flag also lets you batch-verify
  all open PRs for a repo.

  CI iteration loop. Stripe runs local lints in under 5 seconds, applies autofixes, then gives the agent one
  more attempt if CI fails (max 2 rounds). Shipyard's FIX stage does the same: if LINT finds issues (secrets
  committed, missing changelog, version not bumped, test failures), it passes the failures to a Claude session,
  re-runs lint, and caps at 2 attempts.

  Parallel execution. Ramp runs hundreds of sandboxed sessions. Stripe runs parallel devboxes on EC2. Shipyard
  runs --parallel N agents in tmux, each pulling a different task via atomic lock files (mkdir-based), coding in
  isolated git worktrees with agent-labeled output. You don't need hundreds — 3-5 instances burns through a task
  queue fast on a single machine.

  ---
  Where you're still behind

  Gap 1: Environment isolation (MEDIUM impact, HIGH effort)

  Ramp spins up a full sandbox per session: Postgres, Redis, Temporal, RabbitMQ, Chromium, VS Code server. The
  agent has the same environment a human engineer would have locally. Stripe uses pre-warmed EC2 instances that
  provision in 10 seconds.

  Shipyard runs on your Mac. It shares your local state — if a factory run messes up a database or leaves ports
  occupied, it affects your next run or your manual work. Worktrees handle code isolation, and most projects use
  SQLite (file-based, no shared server), so this is less painful than it sounds.

  Closing this would require Docker containers or Modal sandboxes per factory run. For a solo developer, this is
  the one gap where the effort-to-value ratio doesn't justify it yet.

  Gap 2: Observability integration (LOW impact for solo, HIGH for teams)

  Ramp's agent queries Sentry for new errors and Datadog for metric regressions after shipping. Stripe agents
  check CI results and internal dashboards.

  Shipyard checks the dev server and takes screenshots but doesn't watch production metrics post-merge. For a
  solo developer who monitors their own deploys, this matters less. For a team, you'd want the factory to check
  that the deploy succeeded and no new errors appeared.

  Gap 3: Intake breadth (LOW impact for solo)

  Ramp has a Chrome extension where PMs visually select UI elements and request changes. Stripe triggers from
  Slack messages. Shipyard triggers from markdown files and GitHub issues.

  For a solo developer, markdown files are the ideal interface — no context switching, no permissions. For a team,
  Slack or web intake would lower the bar for non-engineers to submit tasks.

  ---
  Where you're actually ahead

  Per-project todo.md. Neither Ramp nor Stripe has publicly described anything like this. Their agents get a
  single prompt or ticket. Shipyard reads the project's own todo file for subtask context, picks the first
  incomplete item, marks it done, and only marks the global task done when all subtasks are complete. More
  granular task management than "here's a Slack message."

  Zero infrastructure. Ramp needs Modal. Stripe needs EC2 devboxes. You need bash factory.sh. One file, no
  dependencies, runs on a laptop.

  Self-healing verify loop. Most enterprise agents run verification as a pass/fail gate. Shipyard's VERIFY stage
  detects failures and triggers a fix session automatically — verify, catch issues, fix, re-verify — before
  marking the task done.

  GitHub issue intake. --issues owner/repo pulls labeled issues into the task queue, and when the factory ships
  a PR, it comments the PR link on the issue and closes it. Lightweight two-way integration without webhooks.

  ---
  What's left

  1. The remaining gaps (environment isolation, observability, intake breadth) are team-scale problems. For a solo
     developer, the factory is functionally at parity with Ramp and Stripe on the core loop.

  2. The next high-value addition would be a post-deploy health check — after the PR merges and deploys, curl
     the production URL, check for 200s, and flag if something breaks. Low effort, closes the observability gap
     for the common case.


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

---
