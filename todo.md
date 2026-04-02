github issues 
tasks folder support
screenshots
fix stage re-run loop
sandbox plan
- CI gate: watch GitHub Actions status after PR, re-run FIX if CI fails
- daemon mode: --watch that polls tasks/ or uses fswatch, auto-processes new files
- streaming live on x with grok as provider
- web dashboard for monitoring tasks and agent status
- switch to opencode or generic agent tooling
- environment isolation: Docker or Modal sandbox per run (Ramp/Stripe parity)
- observability: post-deploy health check against production URL
- intake breadth: Slack, web UI, or PR comment triggers for non-engineer access
- context injection: load target repo CLAUDE.md and representative files into prompt
