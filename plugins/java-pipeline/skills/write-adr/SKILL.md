---
name: write-adr
description: Record an architecture decision as an ADR in docs/adr. Use when a plan or review flags "ADR NEEDED", or when the user makes a design decision worth keeping (dependency choice, integration pattern, data model, consistency strategy).
---

# Write an ADR

1. List `docs/adr/` and take the next number (4 digits, e.g. `0002`).
2. Create `docs/adr/NNNN-short-kebab-title.md` with exactly these sections:

```markdown
# NNNN. <Title in imperative form>

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD
- Deciders: <user's name or "team">

## Context
What forces are at play — requirements, constraints, the problem. 3–8 sentences.

## Decision
What we will do, stated plainly. One paragraph.

## Alternatives considered
- **Option** — why not chosen (one line each, at least two).

## Consequences
- Positive: ...
- Negative / trade-offs: ...
- Follow-ups: rules to add to CLAUDE.md or ArchitectureTest, if any.
```

3. Status is `Proposed` unless the user explicitly accepted the decision.
4. If the decision implies a rule an agent should follow, propose the exact line for
   `CLAUDE.md` (and an ArchUnit rule if it's structural) — but ask before editing either.
