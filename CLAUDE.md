# claude-factory

Start every session by reading `docs/ROADMAP.md`: it has the goal, the status, what's waiting on the owner,
and the next step. Update it in the PR that finishes a step.

- Decisions live in `docs/factory-adr/`. Write one for every significant change.
- Plan before code: put the plan in `docs/plans/<step>.md` and wait for the owner's OK.
- Never push, merge, tag or change GitHub settings without the owner's yes.
- Stage files by path; never `git add -A` / `git add .`.
- Done means factory CI is green: templates build, skills run on fresh projects, the image scan passes.
