# 0030. Usage brake and run ledger

- Status: Accepted
- Date: 2026-11-14
- Deciders: Noel Abi Abdallah (step B6 of [ADR 0020](0020-self-running-factory.md); merging the PR approves it)

## Context
Unattended steps run on the owner's subscription. Nothing recorded what a run cost, and a run that hit the
subscription's usage limit ended as a failed step: the chain (ADR 0026) then refused the same commit, or kept
dispatching into a limit that was still in force. `FACTORY_MAX_BUDGET_USD` caps one run, not the subscription.

## Decision
- **A ledger on the `factory-ledger` branch.** `runs.jsonl`, one JSON record per run: time, run id, step,
  outcome (`published`, `failed` or `usage-limit`), duration, cost, turns, token counts, and for a limit the reset
  time (`resumes_at`, epoch seconds). The branch is an orphan that holds only that file, so it needs no review
  and no CI. A new `ledger` job in `factory-step.yml` writes it with the App's token, on a fresh checkout of the
  base, after the other jobs whatever they did. The outcome and reset time come from job results and outputs;
  only usage numbers come from the agent's result, and each is kept only if it is a number. A failed ledger
  write is a red job that does not hide the run (`continue-on-error`).
- **A usage limit is its own outcome.** The `agent` phase treats an error result whose short text says "usage
  limit", "hit your limit" or "limit reached" as `usage-limit`: it exits 0, nothing is packed or published, and
  the summary says so. A successful report that merely talks about limits, and the budget guard's own error, don't
  count. The reset time is read from the CLI's `|<epoch>` suffix; without one the pause is
  `FACTORY_LIMIT_PAUSE_HOURS` (default 5) from now.
- **Dispatch pauses until the reset.** `resolve` (so a manual run too) and `factory-chain.sh next-step` refuse
  while the ledger's *last* record is a usage-limit run whose reset is still ahead; a later record, or the time
  passing, ends the pause. No ledger yet (404) is not a pause; any other read failure stops the caller.
- **The per-run `FACTORY_MAX_BUDGET_USD` stays** as the runaway guard.
- Tested by `ci/test-factory-step.sh` and `ci/test-factory-chain.sh` with a simulated limit, a fake `gh` and a
  local remote.

## Alternatives considered
- **Commit the ledger to `main`:** every run would add a PR or break the ruleset. A separate branch avoids both.
- **Repository variables for the pause:** needs a token that may write variables; the ledger already carries it.
- **Parse the new "resets 3pm" wording:** it has no date or zone; the fixed pause is the safe fallback.

## Consequences
- Positive: each run's cost and duration are recorded; a limit costs one run, not a failed commit.
- Negative: the chain runs once a day, so a pause that ends at noon is noticed at the next daily run (or a merge
  to `ROADMAP.md`, or a manual dispatch).
- Negative: "the inbox says so" waits for B7, which owns the inbox: until then the pause is in the job summary and
  the ledger, which B7's inbox and digest read.
- Negative: if the ruleset ever covers the `factory-ledger` branch, the ledger job fails (red, nothing lost).
