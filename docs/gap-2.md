The big picture

  Ramp and Stripe are running factories at enterprise scale — hundreds of concurrent sandboxed VMs, integrated
  into Slack/Sentry/Datadog, shipping 30-50% of their merged PRs autonomously. Shipyard is a 150-line shell script
   on your laptop doing the same core loop: task in → code → test → PR out.

  The surprising thing is how much overlap there already is.

  ---
  Where you're at parity

  The pipeline structure is the same. Stripe calls theirs "blueprints" — state machines that mix deterministic
  nodes (git, lint) with agentic nodes (LLM reasoning). Your 12-stage pipeline is exactly this pattern. Stages 1-5
   and 8-12 are deterministic shell commands. Stage 6-7 are agentic. Same architecture, different scale.

  Task intake works. Ramp has Slack, web, Chrome extension, voice. Stripe has Slack and tickets. You have
  todos.md. For a solo developer, a text file you control is arguably better — no infrastructure, no permissions,
  no webhook setup. You reorder tasks by moving lines.

  Branch isolation and PR creation are identical. Everyone creates a feature branch, codes on it, opens a PR. No
  difference here.

  Coding standards enforcement is comparable. Stripe uses scoped rule files per directory (same format as
  Cursor/Claude Code rules). Ramp uses MCP plugins. You use CLAUDE.md per project plus a factory prompt baseline.
  Same concept.

  ---
  Where you're behind — and whether it matters

  Gap 1: Self-verification (HIGH impact)

  This is the biggest difference. After Ramp's agent opens a PR, it takes before/after screenshots with Chromium,
  checks Sentry for new errors, queries Datadog metrics, and checks LaunchDarkly feature flags. It verifies its
  own work using the same tools a human engineer would.

  Shipyard ships the PR and trusts that Claude got it right. No visual check, no error monitoring, no runtime
  verification.

  But you already have the tools: agent-browser for screenshots, /qa for visual QA, /design-review for UI checks.
  The gap isn't capability — it's wiring. A new stage between SHIP and UPDATE that runs agent-browser on a preview
   URL would close this.

  Gap 2: CI iteration loop (HIGH impact)

  Stripe's approach is elegant: after the agent codes, they run local lints in under 5 seconds. If lints fail,
  some have autofixes that get applied automatically. Then CI runs. If CI fails, the agent gets one more attempt
  to fix. Max 2 rounds, then it stops and hands off to a human.

  Your stage 9 FIX exists but is stubbed — it just logs "Skipped." So if Claude's code fails lint or tests, the
  factory reports failure and moves on. It doesn't try to fix itself.

  Implementing this is straightforward: if stage 8 LINT fails, pass the failures to a second claude -p call saying
   "fix these issues," re-run lint, and cap at 3 attempts. Stripe caps at 2.

  Gap 3: Parallel sessions (MEDIUM impact)

  Ramp runs hundreds of sandboxed sessions simultaneously. Stripe runs parallel devboxes on EC2. You run one task
  at a time.

  For a solo developer, you don't need hundreds. But running 3-5 factory instances in parallel would let you burn
  through your todo list faster. You already use tmux and worktrees for parallel Claude sessions. Running
  factory.sh in 3 tmux panes, each pulling a different task, using git worktree instead of git checkout -b, would
  work without any cloud infra.

  The catch: your task picker always grabs the first item. You'd need to add a lock file or task index so parallel
   runners don't pick the same task.

  Gap 4: Environment isolation (MEDIUM impact, HIGH effort)

  Ramp spins up a full sandbox per session: Postgres, Redis, Temporal, RabbitMQ, Chromium, VS Code server. The
  agent has the same environment a human engineer would have locally. Stripe uses pre-warmed EC2 instances that
  provision in 10 seconds.

  Shipyard runs on your Mac. It shares your local state — if a factory run messes up a database or leaves ports
  occupied, it affects your next run or your manual work.

  This is the hardest gap to close. You'd need Docker containers or Modal sandboxes per factory run. For a solo
  developer, worktrees handle the code isolation, and your projects mostly use SQLite (file-based, no shared
  server). So this is lower priority than it sounds.

  Gap 5: Visual verification (MEDIUM impact, LOW effort)

  Ramp takes Chromium screenshots and attaches before/after diffs to PRs. This is really just gap 1
  (self-verification) applied to the UI specifically.

  You have agent-browser and /qa. Adding a screenshot step to the factory would be a few lines in the prompt:
  "after shipping, open the app in agent-browser, take a screenshot, attach to the PR."

  ---
  Where you're actually ahead

  Per-project todo.md is something neither Ramp nor Stripe has publicly described. Their agents get a prompt or a
  ticket. Your factory reads the project's own todo file for detailed subtask context, picks the first incomplete
  item, marks it done, and only marks the global task done when all subtasks are complete. That's a more granular
  task management system than "here's a Slack message."

  Zero infrastructure. Ramp needs Modal. Stripe needs EC2 devboxes. You need bash factory.sh. There's something to
   be said for a factory that's one file, no dependencies, runs on a laptop.

  ---
  What I'd do next

  1. Implement stage 9 FIX — the retry loop. Biggest bang for effort. Makes the factory self-healing.
  2. Add visual verification — wire agent-browser into a post-ship stage. You already have the tool.
  3. Add parallel support — lock file + worktrees so you can run 3 instances in tmux.

  Those three changes would close the high-impact gaps without adding any infrastructure.


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
