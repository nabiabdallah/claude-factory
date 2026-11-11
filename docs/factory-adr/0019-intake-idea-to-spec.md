# 0019. Intake: an idea becomes a spec, in a session or from a labelled issue

- Status: Accepted
- Date: 2026-11-11
- Deciders: Noel Abi Abdallah

## Context
The pipeline starts from a spec, and writing one was manual: `new-feature` drafts "with the user" from the
template, with no guidance on what a buildable spec needs or what to do with points the idea leaves open. An
unattended build (ADR 0018) needs an approved spec on the default branch, so without intake every feature still
began at the owner's keyboard. Roadmap step A3.

## Decision
- **`/java-pipeline:intake <idea>`**: reads the project's rules, ADRs, specs and the code the idea touches, then
  writes `docs/specs/NNNN-name.md` from the template with every section filled. Anything the idea doesn't settle
  becomes an open question with a recommended answer; the skill doesn't decide business rules. The spec stays
  `Draft` until the owner approves; the skill never plans or codes.
- **Label `factory:spec`** on an issue runs the same skill unattended, through the ADR 0018 runner (same workflow
  and script, same pinned plugin and CLI, no GitHub token for the agent). The issue's title and text are written
  to a file the agent reads; they never reach a command line or the prompt.
- **Spec gate:** the run must add exactly one file `docs/specs/NNNN-name.md` and change nothing else. The file
  has every template section, a title, numbered criteria and a status of `Draft` or `Approved`; `Approved` is
  refused while an open question remains.
- **Approval is the merge.** The run opens a pull request (`spec: <name> (#n)`, `Refs #n`). A spec with no open
  questions arrives as `Approved`, so merging approves it; one with open questions arrives as `Draft`, and the
  owner answers them in the file and sets `Approved` before merging.
- **Then build from the same issue:** `factory:build` now also finds the spec path in the issue's comments, but
  only in comments by the workflow or by people who can push (anyone can comment on a public repo). A path in
  the issue text still wins.
- Tested in `ci/test-factory-run.sh` (now 71 cases): the spec gate's refusals, the two approval paths, what is
  published, and which comments count. java-pipeline 0.18.0.

## Alternatives considered
- **Always `Draft`, the owner edits the status** — one more edit on every spec, including those with nothing left
  to decide; the merge is already an explicit approval.
- **Build straight from the idea** — skips the one place where the owner fixes scope and rules before code exists.
- **A separate workflow for specs** — a second copy of the trigger, token and publishing rules to keep in step.
- **Pass the idea in the prompt** — simpler, but the idea is outside text; as a file it is material to read, and
  the gate limits what a run that was talked into something else can change to one spec file.

## Consequences
- Positive: from a phone, an issue and two labels take an idea to a spec PR and then to a code PR.
- Positive: undecided points are visible as questions instead of being settled silently by the agent.
- Negative: an agent can still write a plausible wrong rule into a criterion; the owner's review of the spec PR
  is the control, as it is for a hand-written spec.
- Negative: as with ADR 0018, the real agent call isn't exercised in factory CI.
- Negative: answering open questions means editing the spec file in the PR; there is no question-and-answer
  loop on the issue yet.
