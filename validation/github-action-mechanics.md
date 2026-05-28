# GitHub Action mechanics for `spec-kit-linear-sync.yml`

Reference for FR-027..FR-030 so `/speckit-plan` has concrete inputs.

## 1. Reference YAML

**Runtime: shell + `curl` + `jq` on `ubuntu-latest`.** One HTTP POST
after reading one YAML file — a composite/Docker action adds separate-
repo maintenance for zero gain. `curl`, `jq`, `yq` are preinstalled.

```yaml
# .github/workflows/spec-kit-linear-sync.yml
# Layer E of the spec-kit <-> Linear bridge (FR-027..FR-030).
# Flips spec Issue workflow state on PR open / ready / closed-merged.
# Idempotent with Layer D (reconciliation): failures here are recovered
# on the next sync.

name: spec-kit-linear-sync

on:
  pull_request:
    # `synchronize` and `reopened` intentionally excluded — Layer D
    # handles mid-PR state; reopen does not change phase semantics.
    types: [opened, ready_for_review, closed]

# Minimum scope: contents:read for actions/checkout. No GitHub writes —
# all writes go to Linear via LINEAR_API_TOKEN.
permissions:
  contents: read

jobs:
  sync-linear:
    runs-on: ubuntu-latest
    # Only merged closes flip to "Merged"; drop-close PRs are ignored.
    if: >
      github.event.action != 'closed' ||
      github.event.pull_request.merged == true

    steps:
      - uses: actions/checkout@v4

      - name: Resolve spec + target state
        id: resolve
        env:
          HEAD_REF: ${{ github.event.pull_request.head.ref }}
          ACTION:   ${{ github.event.action }}
        run: |
          set -euo pipefail
          # NNN-... branch pattern; non-feature PRs exit cleanly.
          if [[ ! "$HEAD_REF" =~ ^([0-9]{3,})- ]]; then
            echo "Branch '$HEAD_REF' is not a spec-kit feature branch. Skipping."
            echo "skip=true" >>"$GITHUB_OUTPUT"; exit 0
          fi
          echo "spec_label=speckit-spec:${BASH_REMATCH[1]}" >>"$GITHUB_OUTPUT"
          # State NAME is looked up at runtime — no UUIDs in the file.
          case "$ACTION" in
            opened|ready_for_review) S="Ready-to-merge" ;;
            closed)                  S="Merged" ;;
          esac
          echo "target_state=$S" >>"$GITHUB_OUTPUT"

      - name: Read .specify/extensions/linear/config.yml
        id: config
        if: steps.resolve.outputs.skip != 'true'
        run: |
          set -euo pipefail
          CFG=.specify/extensions/linear/config.yml
          [[ -f "$CFG" ]] || { echo "::error::$CFG missing"; exit 1; }
          PID=$(yq -r '.project_id' "$CFG")
          TID=$(yq -r '.team_id'    "$CFG")
          [[ "$PID" != "null" && -n "$PID" ]] || { echo "::error::project_id missing"; exit 1; }
          [[ "$TID" != "null" && -n "$TID" ]] || { echo "::error::team_id missing"; exit 1; }
          echo "project_id=$PID" >>"$GITHUB_OUTPUT"
          echo "team_id=$TID"    >>"$GITHUB_OUTPUT"

      - name: Flip Linear workflow state
        if: steps.resolve.outputs.skip != 'true'
        env:
          LINEAR_API_TOKEN: ${{ secrets.LINEAR_API_TOKEN }}
          SPEC_LABEL:       ${{ steps.resolve.outputs.spec_label }}
          TARGET_STATE:     ${{ steps.resolve.outputs.target_state }}
          PROJECT_ID:       ${{ steps.config.outputs.project_id }}
          TEAM_ID:          ${{ steps.config.outputs.team_id }}
        run: |
          set -euo pipefail
          if [[ -z "${LINEAR_API_TOKEN:-}" ]]; then
            echo "::error::LINEAR_API_TOKEN missing. Run: gh secret set LINEAR_API_TOKEN -R <owner>/<repo>"
            exit 1
          fi
          api() { curl -sS -X POST https://api.linear.app/graphql \
            -H "Authorization: $LINEAR_API_TOKEN" -H "Content-Type: application/json" --data "$1"; }

          # 1. Locate spec Issue by label + project (FR-004b, FR-028).
          Q=$(jq -nc --arg l "$SPEC_LABEL" --arg p "$PROJECT_ID" '{query:"query($l:String!,$p:ID!){issues(filter:{labels:{name:{eq:$l}},project:{id:{eq:$p}}},orderBy:updatedAt){nodes{id updatedAt}}}",variables:{l:$l,p:$p}}')
          NODES=$(api "$Q" | jq -c '.data.issues.nodes')
          N=$(echo "$NODES" | jq 'length')
          if [[ "$N" == "0" ]]; then
            echo "::warning::No Issue for $SPEC_LABEL in project $PROJECT_ID. Layer D will create it."
            exit 0
          fi
          # FR-004b race semantics: most-recent activity wins; Layer D archives extras.
          IID=$(echo "$NODES" | jq -r 'sort_by(.updatedAt)|reverse|.[0].id')
          [[ "$N" == "1" ]] || echo "::warning::Multiple matches for $SPEC_LABEL; using $IID."

          # 2. Resolve state name -> stateId in this team.
          Q=$(jq -nc --arg t "$TEAM_ID" --arg n "$TARGET_STATE" '{query:"query($t:String!,$n:String!){workflowStates(filter:{team:{id:{eq:$t}},name:{eq:$n}}){nodes{id}}}",variables:{t:$t,n:$n}}')
          SID=$(api "$Q" | jq -r '.data.workflowStates.nodes[0].id // empty')
          [[ -n "$SID" ]] || { echo "::error::State '$TARGET_STATE' missing in team $TEAM_ID — run workspace seed"; exit 1; }

          # 3. issueUpdate.
          M=$(jq -nc --arg i "$IID" --arg s "$SID" '{query:"mutation($i:String!,$s:String!){issueUpdate(id:$i,input:{stateId:$s}){success}}",variables:{i:$i,s:$s}}')
          R=$(api "$M")
          [[ "$(echo "$R" | jq -r '.data.issueUpdate.success // false')" == "true" ]] \
            || { echo "::error::issueUpdate failed: $R"; exit 1; }
          echo "Flipped $IID -> $TARGET_STATE."
```

---

## 2. Runtime / permissions / secrets

**Repo file reads after checkout.** Confirmed: `actions/checkout@v4`
clones into `$GITHUB_WORKSPACE` and subsequent `run:` steps default
their CWD there, so `.specify/extensions/linear/config.yml` is readable
as a plain file. `contents: read` is the documented minimum
([actions/checkout README](https://github.com/actions/checkout)).

**Permissions block — exact set:**

```yaml
permissions:
  contents: read
```

Every other scope omitted. The Action never calls the GitHub API (no PR
comments, no statuses, no Issue mutation); all writes go to Linear via
`LINEAR_API_TOKEN`. Tight scoping per GitHub's hardening guidance
([assigning permissions to jobs](https://docs.github.com/en/actions/using-jobs/assigning-permissions-to-jobs)).
Adding a PR-comment confirmation later requires `pull-requests: write`.

**`pull_request` event.** `opened`, `ready_for_review`, `closed` are
all valid activity types; the canonical `merged == true` filter
discriminates merged closes from drop-closes
([events that trigger workflows](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#pull_request)).

**Secret provisioning (verbatim in install output):**

1. Linear → Settings → API → **Create new personal API key**
   (suggested name: `spec-kit-linear-sync`).
2. Copy token (`lin_api_…`).
3. `gh secret set LINEAR_API_TOKEN -R <owner>/<repo>` and paste.

The bridge MUST NOT perform step 3 (FR-029). Wire format is
`Authorization: <token>` — raw, no `Bearer` prefix
([Linear GraphQL docs](https://linear.app/developers/graphql)).

**Missing/invalid token.** Job fails red. Linear stays at last-known
state. Layer D re-derives merged state from `gh`/git on the next sync
and converges Linear (FR-030 + the "token rotated" edge case). The
bridge does not signal webhook breakage in-band — operators see red
checks in the PR UI.

---

## 3. Failure modes

| Failure | Behaviour | Recovery |
|---|---|---|
| `LINEAR_API_TOKEN` missing | Fail red with `gh secret set` hint | Layer D on next sync |
| Token expired / revoked (401) | curl non-zero, step exits 1 | Rotate token + re-run; Layer D fills gap |
| No Issue matches label | `::warning::`, exit 0 | Layer D creates the Issue on next reconcile |
| Multiple Issues match label | Pick most-recent `updatedAt`, warn; do NOT archive | Layer D archives extras (FR-004b) |
| Target state name missing in team | Fail red, point to workspace-seed step | Run `specify extension seed linear` |
| GraphQL network error / 5xx | Step exits 1, Action red | Layer D on next sync; or re-run job |
| Branch not `NNN-…` | `skip=true`, exit 0 cleanly | N/A — not a spec PR |
| `config.yml` missing | Fail red | Re-run `specify extension add linear` |
| `merged == false` on close | Job filtered by top-level `if:` | N/A — correct |
| Actions disabled on repo | Workflow never fires | Layer D handles via `gh`/git |
| `project_id` points at deleted Project | Filter returns 0; same as "no Issue" | Operator fixes config; Layer D re-creates |

---

## 4. Open questions for `/speckit-plan`

1. **State-name authority.** YAML hard-codes `"Ready-to-merge"` /
   `"Merged"`. Either the seed (FR-021) commits to these exact strings
   or the Action reads a name map from `config.yml`. Pick one before
   tasks are written.
2. **`yq` on self-hosted runners.** Preinstalled on hosted
   `ubuntu-latest`; self-hosted may not have it. Plan should pin
   `mikefarah/yq-action` or fall back to a Python one-liner.
3. **Label filter shape.** Reference YAML uses
   `labels: { name: { eq: … } }` per the Linear filtering docs; the
   `labels: { some: { name: { eq: … } } }` variant exists in some SDKs.
   Smoke-test against a live workspace before plan freezes.
4. **Concurrency group.** Rapid `opened → ready_for_review` can race.
   Reference YAML omits `concurrency:` for simplicity; plan should
   decide whether to add `concurrency: { group: spec-kit-linear-${{ github.event.pull_request.number }}, cancel-in-progress: false }`.
5. **`config.yml` schema.** Reference YAML reads `.project_id` and
   `.team_id` as top-level scalars. Lock the schema before extension-add
   is implemented.
6. **Token recommendation matrix.** Personal API keys are user-scoped
   (full workspace access). FR-029 permits machine-user accounts but
   does not mandate; plan may want guidance per repo class
   (solo / OSS / sensitive).
