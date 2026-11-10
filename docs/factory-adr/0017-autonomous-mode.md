# 0017. Autonomous mode: queued steps go to a PR without per-action approval

- Status: Accepted
- Date: 2026-11-10
- Deciders: Noel Abi Abdallah

## Context
The factory's rules required the owner's OK twice per step (the plan, then the push) and again for each PR.
That keeps the owner in control, but it means no work happens unless he is at the keyboard answering. An
architecture audit on 2026-11-10 (java-pipeline 0.16.0) found the pipeline itself strong and the surroundings
missing: no unattended runs, no intake, few roles, one stack, no measurement of the agents. Closing those gaps
is a long list of steps, and the owner wants to trigger a step and come back to a finished PR.

## Decision
- **A queue in `docs/ROADMAP.md`.** The owner approves steps by putting them in the "Autonomous queue". The
  first six (A1–A6) come from the audit.
- **One trigger, one step, one PR.** The owner starts a session ("Read docs/ROADMAP.md and continue"). The agent
  takes the first unfinished queued step and brings it to a PR with green factory CI.
- **Allowed without asking, for queued steps only:** create a branch, write the ADR, implement, commit, push the
  branch, open the PR, push fixes until CI is green. The plan is the PR description; the merge is the approval.
- **Never without the owner's yes, in any mode:** merge, tag, push to `main`, force-push, change GitHub settings
  or secrets, create or delete a repo, touch `payments-service`.
- **Stop and report** when CI is still red after 3 fix rounds, when the step needs a decision only the owner can
  make, or when finishing would need something on the never list.
- **State lives in the repo.** The roadmap, the ADRs and the PR descriptions carry everything a fresh session
  needs, so a step never depends on an earlier conversation.
- Steps outside the queue keep the old rule: plan in `docs/plans/<step>.md`, wait for the owner's OK.

## Alternatives considered
- **Keep per-action approval** — safest, but the owner is the bottleneck for every push.
- **A nightly scheduled run** — works while the owner sleeps, but he prefers to decide when a step starts.
- **Let the agent merge when CI is green** — fastest, but removes the only human review; rejected.

## Consequences
- Positive: a step costs the owner one trigger and one review.
- Positive: the "never" list is short and can be enforced mechanically by rulesets on `main` and on release
  tags (roadmap step #1), so it doesn't rest on the agent's good behaviour.
- Negative: until those rulesets exist, "never merge" is a rule the agent follows, not one GitHub enforces.
- Negative: a wrong plan is found at PR review, after the work is done, instead of before it.
- Negative: in a cloud session factory CI is the only build check, so each fix costs a CI round trip.
