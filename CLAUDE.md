# claude-factory

Start every session by reading `docs/ROADMAP.md`: it has the goal, the status, what's waiting on the owner,
and the next step. Update it in the PR that finishes a step.

- Decisions live in `docs/factory-adr/`. Write one for every significant change.
- Plan before code. For a step in the roadmap's autonomous queue, the plan is the PR description and the owner's
  merge is the approval. For anything else, put the plan in `docs/plans/<step>.md` and wait for the owner's OK.
- Autonomous mode (ADR 0017): when the owner says "go", take the next queued step to a PR without asking along
  the way. Allowed: create a branch, commit, push that branch, open a PR, push fixes until factory CI is green.
- Never, in any mode, without the owner's yes: merge, tag, push to `main`, force-push, change GitHub settings or
  secrets, create or delete a repo, or touch `payments-service`.
- Stop and report instead of guessing when: CI is still red after 3 fix rounds, the step needs a decision only
  the owner can make, or finishing it would need something on the never list.
- Stage files by path; never `git add -A` / `git add .`.
- Done means factory CI is green: templates build, skills run on fresh projects, the image scan passes.
