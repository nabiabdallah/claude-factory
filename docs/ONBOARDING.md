# Onboarding: from an empty machine to a deployed change

Each step has the command and a check that it worked. Paths assume the factory is cloned to
`~/dev/factory/claude-factory` and projects live in `~/dev/projects`. Decisions behind each step are in
[factory-adr](factory-adr/); what's next for the factory is in [ROADMAP.md](ROADMAP.md).

## 1. Machine prerequisites (once)

| Tool | Install | Check |
|---|---|---|
| Java 21 | `curl -s https://get.sdkman.io \| bash`, then `sdk install java 21-tem` | `java -version` → 21 |
| jq (the plugin hooks parse JSON with it) | your package manager | `jq --version` |
| GitHub CLI | your package manager, then `gh auth login` | `gh auth status` |
| Claude Code | see claude.com/claude-code | `claude --version` |

No global Maven: every project has `./mvnw`. No Docker: tests use an embedded Postgres, images are built by Jib in CI.

## 2. Read access to the shared build (once)

Services inherit `factory-parent` from GitHub Packages ([ADR 0003](factory-adr/0003-shared-parent-pom-on-github-packages.md)).

1. Create a classic personal access token with only `read:packages`.
2. Put it in `~/.m2/settings.xml`, then `chmod 600 ~/.m2/settings.xml`:
   ```xml
   <settings><servers><server>
     <id>github</id><username>nabiabdallah</username><password>TOKEN</password>
   </server></servers></settings>
   ```
3. Allow `maven.pkg.github.com` and `github-registry-files.githubusercontent.com` (where GitHub serves the package
   files) in the Claude Code sandbox: `sandbox.network.allowedDomains` in `~/.claude/settings.json`.

**Check:** in the factory, `cd plugins/java-pipeline/templates/skeleton && ./mvnw -q validate` succeeds (it
resolves the parent from GitHub Packages).

## 3. Install the plugin (once)

```bash
claude plugin marketplace add nabiabdallah/claude-factory   # or the local clone: ~/dev/factory/claude-factory
claude plugin install java-pipeline@claude-factory
```

**Check:** `claude plugin list` shows `java-pipeline@claude-factory` enabled; `claude plugin details java-pipeline`
lists the skills, agents and hooks.

## 4. Create a service

In a Claude Code session:

```
/java-pipeline:new-project customer-service com.example.customers
```

It copies the skeleton template (or `--template payments-example`), renames packages and the artifact, runs
`./mvnw verify` and makes the first commit. The project's `.claude/settings.json` pins the plugin to the release
that created it (`"ref": "java-pipeline-vX.Y.Z"`, [ADR 0015](factory-adr/0015-releases-and-pinned-plugin.md)).

**Check:** `cd ~/dev/projects/customer-service && ./mvnw verify` is green; `claude` there offers to install or
enable the plugin if it's missing.

## 5. Put it on GitHub

**Or let the factory do steps 4, 5 and 7's setup** ([ADR 0024](factory-adr/0024-service-provisioning.md)):
`gh workflow run new-service.yml --repo nabiabdallah/claude-factory -f name=customer-service -f
package=com.example.customers`. It scaffolds from the latest release, creates the public repo, sets its secrets
and labels, adds the factory's App and applies the guardrails. The by-hand route follows.

```bash
git config user.email 99053318+nabiabdallah@users.noreply.github.com   # public repo: no private email in commits
gh repo create nabiabdallah/customer-service --public --source . --push
gh secret set FACTORY_PACKAGES_TOKEN --repo nabiabdallah/customer-service                    # Actions
gh secret set FACTORY_PACKAGES_TOKEN --app dependabot --repo nabiabdallah/customer-service   # Dependabot
~/dev/factory/claude-factory/ci/protect-repo.sh nabiabdallah/customer-service service       # after the first green CI run
```

Both secrets hold the same `read:packages` token; GitHub doesn't pass them to PRs from forks, so a fork PR fails
`verify` instead of reading them. Repos are public because rulesets and secret scanning are free only there
(ADR 0016). `protect-repo.sh` needs your admin `gh` login and sets: `main` only through a PR with `verify` and
`manifests` green and the branch up to date (0 approvals; admins may bypass only through a PR), secret scanning
with push protection, Dependabot alerts and security updates, private vulnerability reporting, CodeQL (Java and
Actions), approval for fork-PR workflows from all outside contributors, and a read-only workflow token. Re-run it
any time to restore them. It also allows Actions to open pull requests, which the unattended runner needs (with 0
required approvals that grants nothing more).

**Check:** the first CI run on `main` is green: `verify` (tests, ArchUnit, Enforcer, coverage floor, Spotless),
the image scan, `manifests` (deploy gate), and `image` (pushes `ghcr.io/nabiabdallah/customer-service:<sha>`,
signed with cosign). After `protect-repo.sh`, `gh api repos/nabiabdallah/customer-service/rulesets` lists `main`,
and `git push origin main` is rejected.

## 6. Optional capabilities

Each runs once, from the project root, on a clean branch, and leaves its changes uncommitted for review:

```
/java-pipeline:add-postgres          # Postgres + Flyway + JdbcClient; embedded Postgres in tests
/java-pipeline:add-resource-server   # OAuth2/JWT: AUTH_ISSUER_URI (https), <service>:read / :write scopes
```

**Check:** the skill ends with `./mvnw verify green`. add-postgres may print an ArchUnit rule for you to add to
`ArchitectureTest` (agents may not edit that file).

## 7. Build a feature

```
/java-pipeline:new-feature Add GET /customers/{id}. Write the spec first.
```

The pipeline: a spec in `docs/specs/` (you approve it) → plan → architect-reviewer → failing tests (test-writer)
→ implementation → `./mvnw verify` (the Stop hook won't let the session finish while it's red) → code-reviewer →
PR. You approve the spec and the plan, and you merge.

**Unattended** ([ADR 0018](factory-adr/0018-headless-feature-runs.md)): the same pipeline in GitHub Actions,
started by a label. Once per repo:

```bash
claude setup-token                                                  # prints a one-year token for your subscription
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo nabiabdallah/customer-service
gh label create factory:build --repo nabiabdallah/customer-service --description "Build this issue's approved spec"
gh label create factory:spec --repo nabiabdallah/customer-service --description "Draft a spec from this issue's idea"
```

Optional: the secret `FACTORY_PR_TOKEN` (a fine-grained token for this repo, Contents and Pull requests read and
write) so CI starts on the PR by itself, and the variable `FACTORY_MAX_BUDGET_USD` (default 25 per run).

Then, per feature, from an idea ([ADR 0019](factory-adr/0019-intake-idea-to-spec.md)): open an issue that
describes it and add the label `factory:spec`. The run opens a spec PR: answer any open questions in the file, make
sure it says `- Status: Approved`, and merge. Then add `factory:build` to the same issue.

Or with a spec you wrote (in a session: `/java-pipeline:intake <idea>`): merge it with `- Status: Approved` to
`main`, open an issue whose text contains its path (`docs/specs/0002-get-customer.md`), and add `factory:build`. The run ends with a comment on the issue:
the PR, or the phase and reason it stopped. To retry, fix the cause, delete the `factory/issue-<n>` or `factory/spec-<n>` branch if
one was pushed, then remove and re-add the label.

**Check:** the issue gets "Factory run finished: … is ready for review", and the PR's description maps each
acceptance criterion to its tests. Without `FACTORY_PR_TOKEN`, close and reopen the PR to start CI.

## 8. Deploy

Once per cluster ([ADR 0012](factory-adr/0012-deploy-safety.md), [ADR 0014](factory-adr/0014-observability-prometheus-otel.md)):
- namespaces `customer-service-staging` and `customer-service-prod`;
- the database Secret `customer-service-db` in each (`DB_URL`, `DB_USERNAME`, `DB_PASSWORD`), if you added Postgres;
- label the ingress controller's namespace `claude-factory/ingress=true`, and Prometheus' and the OpenTelemetry
  Collector's namespace `claude-factory/monitoring=true`;
- set the Collector address in `deploy/k8s/base/deployment.yaml` (placeholder `otel-collector.monitoring:4318`).

Promote with a PR that sets `newTag` in `deploy/k8s/overlays/<env>/kustomization.yaml` to a commit on `main`; CI
(`manifests`) checks it. Then `kubectl apply -k deploy/k8s/overlays/<env>`. A release that crosses a
`-- rollout: recreate` migration needs `components/recreate` in that overlay (CI tells you).

**Check:** `kubectl -n customer-service-staging rollout status deployment/customer-service`.

## 9. Upgrading a service

- **Plugin:** read [the plugin changelog](../plugins/java-pipeline/CHANGELOG.md) (especially **Upgrading**), then
  set `ref` in `.claude/settings.json` to the new `java-pipeline-vX.Y.Z` and start a new session. Template changes
  (CI, manifests, tests) don't reach existing services by themselves; the changelog says what to copy.
- **Shared build:** Dependabot opens a PR when a new `factory-parent` is published; read
  [its changelog](../parents/factory-parent/CHANGELOG.md) before merging.

## Troubleshooting (this machine: WSL + the Claude Code sandbox)

- **Maven Central returns 502 through the sandbox proxy.** Run Maven outside the sandbox:
  `source ~/.sdkman/bin/sdkman-init.sh; ./mvnw …`.
- **`gh` fails inside the sandbox.** Its config directory is denied; run it outside. Its token has no
  `read:packages` or `delete_repo` scope, so check private GHCR images from a workflow in the repo.
- **Downloads from `release-assets.githubusercontent.com` fail.** Trivy and cosign run only in CI. Get a release
  asset's sha256 with `gh api repos/<o>/<r>/releases/tags/<t> --jq '.assets[]|.digest'`.
- **A PR opened by Actions with `GITHUB_TOKEN` didn't start CI.** That's GitHub's rule; close and reopen it.
- **Empty dotfiles (`.bashrc`, `.claude/`, …) appear in the repo root.** Sandbox placeholders: never stage them
  (stage by path, never `git add -A`).
