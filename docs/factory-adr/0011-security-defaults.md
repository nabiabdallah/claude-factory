# 0011. Security defaults: https issuer, required subject, caller isolation in reviews

- Status: Accepted
- Date: 2026-11-04
- Deciders: Noel Abi Abdallah

## Context
ADR 0008 left a plain-http issuer allowed (needed by the tests' stand-in on 127.0.0.1), so a misconfigured
`AUTH_ISSUER_URI` would download signing keys without TLS. The payments-service spec 0005 reviews (per-account
authorization) found mistakes that no template code catches: data reachable by another customer, business
errors that reveal someone else's state, idempotency keys shared across callers, and tokens without a usable
`sub`. Those are design and review problems, so the fix is mostly in the agents and the spec template.

## Decision
- **https issuer** (add-resource-server's `SecurityConfig`): `AUTH_ISSUER_URI` must be https; plain http only to
  a loopback host as written (`localhost`, `127.x.y.z`, `[::1]`), never resolved. Startup fails otherwise
  (message names the variable, shows scheme/host/port only). The same rule runs on every call of the identity
  provider client (discovery and JWKS), so a discovery document can't move the key download to plain http.
- **Required `sub`**: a token validator refuses tokens whose `sub` is missing, blank, over 255 characters or
  contains control characters (401). Per-caller rules and stored keys depend on it.
- **Caller isolation in the pipeline**: the spec template gains an Authorization section; the architect and
  code reviewers check that the caller comes from the token into the command, ownership is checked before any
  other rule, not-owned answers like not-found and lists are filtered; the test-writer adds second-caller tests;
  ownership checks join the new-feature mutation list.
- **Idempotency keys per caller**: guidance in the templates' and the resource server's `CLAUDE.md` and in both
  reviewers: unique per (caller, key), with a two-caller test.
- Tests (generated, run by the factory CI smoke step): `IdentityProviderTransportTest` (rule cases incl.
  `127.0.0.1.evil.example`, `127.0.0.1@evil.example`, `127.1`; client refuses plain http before connecting),
  `StartupGuardsTest` (plain-http issuer, no credential echo; https starts), `SecurityTest` (unusable `sub` → 401,
  255 chars → 200). Mutation-checked: 8/8 caught (startup check, interceptor, wide loopback match, each `sub` rule).

## Alternatives considered
- **Allow http under the `local` profile** (the roadmap wording): a profile is a switch that can be set in a
  cluster by mistake; a loopback host can't reach a remote IdP. Loopback also covers tests with no escape hatch.
- **Resolve the host and check for a loopback address**: depends on DNS at startup and on the machine; a name
  can resolve to loopback here and elsewhere not.
- **Ownership in template code**: the templates have no caller until add-resource-server runs, and ownership is
  domain-specific (payments-service spec 0005 shows one shape); guidance plus review checks fit every domain.

## Consequences
- Positive: a non-TLS issuer can't go unnoticed; tokens without a caller are refused; the pipeline asks the
  cross-customer questions at spec, plan, test and review time.
- Negative: an in-cluster IdP over plain http (e.g. `http://keycloak:8080`) is refused; it needs TLS.
- Services generated before java-pipeline 0.12.0 don't get the code changes automatically (port by hand if wanted).
