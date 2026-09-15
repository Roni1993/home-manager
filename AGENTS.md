## Agent skills

### Issue tracker

Issues live as GitHub issues in this repo (Roni1993/fleek). Use the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context. `CONTEXT.md` at the repo root + `docs/adr/`. See `docs/agents/domain.md`.

### Change delivery

Every repository change must be committed, pushed to a branch, and wrapped up in a GitHub pull request. Do not leave completed changes only in the local worktree or branch. Skip this workflow only when the user explicitly requests no commit, no push, or no pull request.
