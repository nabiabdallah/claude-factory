# claude-factory

Start every session by reading `docs/ROADMAP.md`: it has the goal, the status, what's waiting on the owner,
and the next step. Update it in the PR that finishes a step.

- Decisions live in `docs/factory-adr/`. Write one for every significant change.
- Plan before code. For a step in the roadmap's autonomous queue, the plan is the PR description and the owner's
  merge is the approval. For anything else, put the plan in `docs/plans/<step>.md` and wait for the owner's OK.
- Autonomous mode (ADR 0017): when the owner says "go", take the next queued step to a PR without asking along
  the way. Allowed: create a branch, commit, push that branch, open a PR, push fixes until factory CI is green.
- Never, in a session, without the owner's yes: merge, tag, push to `main`, force-push, change GitHub settings or
  secrets, create or delete a repo, or touch `payments-service`.
- Factory workflows (ADR 0020), once the B0 rulesets are in place, may: merge a `risk:low` PR on green checks and
  an independent reviewer APPROVE, tag a release from a merged version bump, provision a service repo with its
  secrets and labels, and start the next queued step. Never, from anything: merge a `risk:high` PR, change
  rulesets, the tier classifier, the App's permissions or where secrets come from, delete a repo, force-push.
- Stop and report instead of guessing when: CI is still red after 3 fix rounds, the step needs a decision only
  the owner can make, or finishing it would need something on the never list.
- Headless step runs (`FACTORY_HEADLESS=1`, ADR 0022): nobody can answer. Do only the step the prompt names.
  Commit on the current branch; don't push, open PRs, tag or call GitHub (you hold no GitHub token; the workflow
  publishes). Before finishing, run the factory checks your change touches (`ci/*.sh`, `ci/check-docs.sh`,
  template builds with `./mvnw`, no sandbox wrapper needed). Write the PR description to `$FACTORY_REPORT`:
  first line `# <conventional PR title>`, then the plan, the changes by file, what you ran with its result, and
  what the owner must do after merging. Update the roadmap as for any step. If the step needs the owner's
  decision or something on the never list, say so in the report and stop.
- Stage files by path; never `git add -A` / `git add .`.
- Done means factory CI is green: templates build, skills run on fresh projects, the image scan passes.
