# Linear ↔ GitHub Integration Survey

Research for FR-027..FR-030 (GitHub Actions webhook on PR
open/ready/merged calling Linear directly). Goal: mirror what works.

## 1. Linear's official GitHub integration (GitHub App)

<https://linear.app/docs/github>, <https://github.com/marketplace/linear>,
<https://linear.app/integrations/github>.

- **Events**: PR `drafted`, `opened`, `review_requested`,
  `ready_for_review`, `merged`; commits to any branch and to default;
  branch creation.
- **PR → Issue mapping** (in order): (1) Linear ID in **branch name**
  e.g. `ENG-123-feature` — Linear's UI ships `Cmd/Ctrl+Shift+.` to
  copy branch names in exactly this form; (2) Linear ID in **PR
  title**; (3) **magic words** in PR description or commit message:
  `fixes|closes|resolves|implements ENG-123` (closing) or
  `ref|references|part of ENG-123` (non-closing).
- **Event → action** (per-team overridable defaults):
  - PR opened or first commit pushed → Issue **In Progress**
  - PR ready for merge → configurable (often "In Review")
  - PR merged or commit reaches default → Issue **Done**
  - Per-target-branch rules: `staging → In QA`, `main → Deployed`.
- **Comment format**: an **attachment-style linkback card** on the
  Issue containing PR title, description, reviewer avatars, review
  state, preview deploy links — not free text. Titles can be
  redacted for private teams.
- **Label sync**: bidirectional for **GitHub Issues** synced to
  Linear (title/description/status/assignee/labels/sub-issues/
  comments). **PR labels do not sync.**
- **Auth**: GitHub App (not PAT). Org owner or repo admin installs;
  each individual must also OAuth-link their personal GitHub account
  for attribution. One GitHub account per Linear workspace.
- **Failure modes**: out-of-sync → disconnect + `linear.app/reset` +
  reconnect. "Ready for merge" silently never fires without branch
  protection (GitHub never reports `mergeable=true`). Squash-merging
  multiple PRs drops the linkback.

## 2. `linear/linear-release-action` (only first-party Linear action)

<https://github.com/linear/linear-release-action>,
<https://github.com/marketplace/actions/linear-release>,
<https://github.com/linear/linear-release>.

There is no `linear/setup-linear`.

- **Purpose**: commits → Linear **Releases** (not Issues).
- **Trigger**: caller's choice; typical `push:` to `main` or
  `release:` published.
- **Mapping**: scans commit messages for `TEAM-NNN` IDs; needs
  `actions/checkout@v4` with `fetch-depth: 0`.
- **Secret**: single `LINEAR_ACCESS_KEY` (pipeline access key) via
  the `access_key:` input. No OAuth.
- **Failure modes**: Windows unsupported; missing `fetch-depth: 0`
  silently matches zero issues.

Shape worth mimicking:

```yaml
- uses: actions/checkout@v4
  with: { fetch-depth: 0 }
- uses: linear/linear-release-action@v0
  with: { access_key: ${{ secrets.LINEAR_ACCESS_KEY }} }
```

## 3. Community bridge — `NomicFoundation/github-linear-bridge`

<https://github.com/NomicFoundation/github-linear-bridge>.

- **Workflows**: `create-linear-issue.yml` on new GH issue or
  external-contributor PR creates Linear Issue, assigns random
  maintainer both sides, **comments on the GH issue/PR with Linear
  ID + URL** (this handshake comment IS the durable join key — no
  state file). `close-linear-issue.yml` on GH close → closes Linear
  Issue.
- **Mapping**: no branch convention; relies on GH-side comment.
- **Secrets**: `LINEAR_API_KEY`, `LINEAR_TEAM_ID`, `MAINTAINERS`
  (semicolon-separated).
- **Failure modes**: README warns "may completely fail … without
  previous notice." No idempotency claim.

`korosuke613/linear-webhook` (thin Node `WebhookHandler`) confirms
Linear's emitted payload shape but isn't itself a bridge.

## 4. Webhook security patterns

<https://docs.github.com/en/actions/reference/security/secure-use>,
<https://docs.github.com/en/rest/authentication/keeping-your-api-credentials-secure>,
<https://github.com/orgs/community/discussions/168661>.

- **Storage**: every surveyed integration uses a **per-repo
  secret** (`LINEAR_API_KEY` / `LINEAR_ACCESS_KEY`); none uses
  org-level secrets because Linear scopes are workspace-wide and a
  leak gives full workspace write.
- **Identity**: two accepted patterns — operator's personal API key
  (low friction, high blast radius) **or** a dedicated **machine
  user** (recommended for shared/OSS repos; endorsed by GitHub's own
  docs).
- **Rotation**: 30 / 60 / 90 days for critical / high / normal per
  GitHub guidance; staged rotation (mint → flip secret → revoke).
- **OAuth alternative**: only Linear's first-party GitHub App offers
  short-lived OAuth; any self-hosted webhook is stuck with a
  long-lived API key.

## Patterns we should adopt

1. **Use branch name as the join key, mirroring the GitHub App.**
   Our branches are already `001-spec-kit-linear-bridge`; parse the
   leading `NNN` and look up by workspace label `speckit-spec:NNN`
   (FR-004b) scoped to the Project UUID. No PR-title or
   commit-message parsing — matches FR-028 exactly.
2. **Single per-repo secret `LINEAR_API_TOKEN` with machine-user
   path documented (FR-029).** Copy
   `linear-release-action`'s shape: `access_key:` input + repo
   secret. Default the install docs toward machine-user for any
   repo with external contributors; personal key for solo repos.
3. **Linkback-style structured comment, not free-text status.** On
   PR open, post **one** structured comment on the spec Issue with
   PR URL / title / draft-or-ready flag / author, formatted like
   Linear's own attachment card. On merge, **edit that same
   comment** to append merge SHA + timestamp — do not append a
   second comment. Keeps FR-008's comment stream coherent.
4. **Webhook layer never mutates labels.** Linear's GitHub App
   deliberately does not sync PR labels onto Issues; mimic that.
   Reconciliation (Layer D) owns `phase:*` and `speckit-spec:NNN`;
   the webhook (Layer E) flips workflow state only. Prevents two
   writers fighting over the same label set.
5. **Fail loud, never retry — let reconciliation be the safety net.**
   Match `linear-release-action`'s posture: missing/invalid secret
   → red-X in GH Actions UI, exit non-zero, no retry, no DLQ. Spec
   edge cases at lines 305–310 already commit to this. Concretely:
   one Linear API call per event in the workflow YAML; if it fails,
   Layer D (per FR-030) converges on next reconcile.
