# 0029. Scope freeze and a definition of done

- Status: Accepted
- Date: 2026-11-14
- Deciders: Noel Abi Abdallah

## Context
Twelve days in (first commit 2026-11-02), the factory has 28 merged pull requests and 28 ADRs, and it has built
one thing: a greeting endpoint on demo-service. The work felt stuck for three reasons:
- **The end kept moving.** Seven hardening items, then the audit of 2026-11-10 (A1–A6), then the audit of
  2026-11-12 (B0–B7), then C1. Each audit found real gaps, and each added steps.
- **Nothing outside the factory needed it yet.** With no real application, no step could be judged "good enough",
  and defects showed only at acceptance (0.19.1, 0.19.2, 0.20.1, the B6 runner failure).
- **The roadmap had a goal but no finish line**, so "how long until it is done" had no answer.

## Decision
The owner froze the scope on 2026-11-14.
- **Done means:** one real application of the owner's goes from a spec to running on a cluster, built by the
  factory, and gets one week of unattended maintenance.
- **The queue to get there is B6, B7 and a minimal C1** (a small cluster, a CD job, a post-deploy check). Nothing
  is added to it before done.
- **Deferred until the real application shows a need:** A6 (evals), A4 (orchestrator and implementer split), A5
  (domain rules out of the agents), the frontend and Python pipelines, more roles, the learning loop. Their rows
  stay in the roadmap marked "(deferred)", which the chain does not run.
- **The first real application starts now**, in parallel: the spec-to-PR path already works for a Java backend.
  The owner names it.
- A defect that blocks the frozen queue or the real application is fixed when found; that is not new scope.

## Alternatives considered
- **Finish the whole roadmap first** (A4–A6, the frontend pipeline): five to seven more weeks by the pace so far,
  still with no application to judge it by.
- **Stop factory work now and only build the application:** deploy and maintenance are the two parts of the
  owner's goal that don't exist yet; B7 and C1 are what provide them.

## Consequences
- Positive: there is a finish line, about two weeks of work by the pace so far (an estimate, not a measurement).
- Positive: what comes after is chosen from what the real application needed, not from another audit.
- Negative: once B5 auto-merges, agent behaviour is still unmeasured until A6. The required checks and the
  independent reviewer are the only guard.
- Negative: an application that needs a UI has no pipeline for it; the UI is built outside the factory or waits.
