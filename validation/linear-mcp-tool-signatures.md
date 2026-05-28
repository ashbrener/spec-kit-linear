# Linear MCP tool signatures & GraphQL fallback — 2026-05-27

Drilldown for spec 001-spec-kit-linear-bridge. Resolves the YELLOW items
from `linear-mcp-capability-check.md` to literal tool names, parameter
schemas, and GraphQL fallback definitions.

Server: `https://mcp.linear.app/mcp` (Streamable HTTP, MCP spec
2025-03-26). The catalogue below is the official Linear MCP, not a
third-party fork.

## 1. Per-capability tool signatures

The official MCP exposes ~23 base tools (Fiberplane audit) plus the
Feb 2026 additions for milestones, initiatives, project updates, and
project labels — roughly 28-31 total. Tool names use `snake_case`; there
is **no** unified `save_issue` mutation — create and update are split.

### Capability 1 — Create/update Project (markdown description)

```
create_project(name: string, teamIds: string[],
               description?: string, leadId?: string,
               targetDate?: string, statusId?: string,
               labelIds?: string[], milestones?: object[]) -> Project
update_project(projectId: string, name?: string,
               description?: string, statusId?: string,
               labelIds?: string[], leadId?: string,
               targetDate?: string) -> Project
```

The `description` field is markdown-native at the GraphQL layer
(`ProjectUpdateInput.description: String`, `content: String` "project
content as markdown"), so the MCP passes through markdown unchanged.
**Markdown probe (item #3 in YELLOW) is resolved as YES** by schema
introspection.

### Capability 2 — Create/update Issue in a Project

```
create_issue(teamId: string, title: string,
             description?: string, projectId?: string,
             projectMilestoneId?: string, parentId?: string,
             stateId?: string, priority?: number,
             assigneeId?: string | "me", labelIds?: string[],
             cycleId?: string, dueDate?: string) -> Issue
update_issue(issueId: string, title?: string, description?: string,
             projectId?: string, projectMilestoneId?: string,
             stateId?: string, priority?: number,
             assigneeId?: string | "me", labelIds?: string[],
             cycleId?: string) -> Issue
```

Per `IssueCreateInput` / `IssueUpdateInput` in the Linear schema
(lines 16152, 19827), `projectMilestoneId: String` is a first-class
field on both inputs.

### Capability 3 — Attach Issue to Project Milestone

**Resolved YES** (no probe needed). `update_issue` accepts
`projectMilestoneId`. Schema-confirmed.

### Capability 4 — Blocks / blocked-by relations

**GAP. No MCP tool.** Must use GraphQL `issueRelationCreate`. See §2.

### Capability 5 — Set Project Status

**Resolved YES** with caveat. Project Status is a *relation*, not an
enum: `ProjectUpdateInput.statusId: String` (line 33802). You set it by
passing `statusId` to `update_project`. The status IDs themselves come
from `list_project_statuses` (or GraphQL `projectStatuses`) and map to
one of six `ProjectStatusType` enum values: `backlog`, `planned`,
`started`, `paused`, `completed`, `canceled`.

Operational note: Status objects are per-workspace, user-defined records
seeded from the type enum. The bridge must first resolve a desired
status (e.g. "Started") to its workspace-scoped `id` before calling
`update_project`. Cache this map.

### Capability 6 — Labels on Projects & Issues

```
list_project_labels() -> ProjectLabel[]
list_issue_labels() -> IssueLabel[]
create_issue_label(name: string, teamId?: string, color?: string)
                                                  -> IssueLabel
```

Project labels added in Feb 2026 changelog. Setting labels on issues or
projects is done via `labelIds: string[]` on `create_issue` /
`update_issue` / `create_project` / `update_project`.

### Capability 7 — Comments on Projects & Issues

```
create_comment(issueId?: string, projectId?: string,
               projectUpdateId?: string, parentId?: string,
               body: string) -> Comment
```

**Resolved YES for projects.** `CommentCreateInput` (line 4416) exposes
`projectId: String` and `projectUpdateId: String` — so the same
`create_comment` MCP tool handles both Issue and Project comments. The
"projectCommentCreate" mutation name guessed in the prior validation
does **not** exist; it's `commentCreate` with `projectId` set.

### Capability 8 — Create custom Workflow States

**GAP. No MCP tool.** Must use GraphQL `workflowStateCreate`. See §2.

### Capability 9 — Create Project Milestones

```
create_project_milestone(projectId: string, name: string,
                         description?: string, targetDate?: string,
                         sortOrder?: number) -> ProjectMilestone
update_project_milestone(milestoneId: string, name?: string,
                         description?: string, targetDate?: string)
                                                  -> ProjectMilestone
```

Added Feb 2026. Schema-backed by `ProjectMilestoneCreateInput`.

### Additional tools available (not in capability matrix but useful)

`list_issues`, `list_projects`, `list_teams`, `list_users`,
`list_documents`, `list_cycles`, `list_comments`, `list_issue_statuses`,
`get_issue`, `get_project`, `get_team`, `get_user`, `get_document`,
`get_issue_status`, `search_documentation`, plus Feb 2026
initiative / project update tools.

## 2. GraphQL fallback (confirmed from `schema.graphql` HEAD)

All three gaps go through `@linear/sdk`, which auto-generates a wrapper
per mutation (`client.issueRelationCreate(input)` etc.) — no raw
GraphQL strings required.

### `issueRelationCreate`

```graphql
mutation { issueRelationCreate(input: IssueRelationCreateInput!,
                               overrideCreatedAt: DateTime)
                              : IssueRelationPayload! }

input IssueRelationCreateInput {
  id: String                 # optional, UUIDv4 (idempotency handle)
  issueId: String!           # UUID or "LIN-123"
  relatedIssueId: String!    # UUID or "LIN-123"
  type: IssueRelationType!   # blocks | duplicate | related | similar
}
```

`type: blocks` creates the "blocks → blocked by" pair atomically.
Pass a stable `id` (UUIDv4 derived from the task pair) to make the
mutation idempotent.

### `workflowStateCreate`

```graphql
mutation { workflowStateCreate(input: WorkflowStateCreateInput!)
                              : WorkflowStatePayload! }

input WorkflowStateCreateInput {
  id: String           # optional UUIDv4
  name: String!
  color: String!       # hex, required
  type: String!        # backlog|unstarted|started|completed|canceled
  teamId: String!      # states are scoped to a team, NOT workspace
  description: String
  position: Float
}
```

Critical: workflow states are **team-scoped**, not workspace-scoped.
The bridge must create the 10 phase states once per team that uses the
tracker pattern. Use a deterministic `id` per (teamId, phaseName) to
make creation idempotent across re-runs.

### Project comments — `commentCreate` (NOT a separate mutation)

```graphql
mutation { commentCreate(input: CommentCreateInput!): CommentPayload! }

input CommentCreateInput {
  body: String                    # markdown
  issueId: String                 # OR
  projectId: String               # OR
  projectUpdateId: String         # OR
  initiativeId: String
  parentId: String                # for threading
  id: String                      # idempotency
  createAsUser: String            # actor=app OAuth only
  doNotSubscribeToIssue: Boolean
}
```

Available as a regular MCP tool (`create_comment`) — so this is NOT
actually a GraphQL-only path. Demoted from "gap" to "covered by MCP".

### Rate limit note

OAuth-app token: 5,000 req/hr/user + 2M complexity points/hr; per-query
ceiling 10k complexity points. Headers `X-RateLimit-Requests-*`,
`X-RateLimit-Complexity-*`, `X-RateLimit-Endpoint-*`. Errors return
HTTP 400 with `RATELIMITED` code — no documented Retry-After header,
so implement exponential backoff. Mutations have unpublished
per-endpoint sub-limits; respect `X-RateLimit-Endpoint-Remaining`.

## 3. Items previously needing runtime probe — all resolved

| Probe | Result | Source |
|---|---|---|
| Markdown in Project description | YES | `ProjectUpdateInput.description: String` + `.content: String` (markdown) |
| `update_project` sets Status | YES via `statusId` (not enum) | `ProjectUpdateInput.statusId: String` line 33802 |
| `update_issue` accepts `projectMilestoneId` | YES | `IssueUpdateInput.projectMilestoneId: String` line 19899 |

No runtime probe required before plan lock.

## 4. Authentication surface

**Official MCP supports both** OAuth 2.1 (interactive, dynamic client
registration) **and** static API keys via `Authorization: Bearer
<token>` header (Linear MCP docs). Personal API keys → 5,000 req/hr.
OAuth app tokens → same 5,000 req/hr. Unauthenticated 600/hr.

**OAuth scopes** (Linear OAuth 2.0 docs):
- `issues:create` — create issues + attachments
- `comments:create` — create comments
- `write` — broad write (covers projects, milestones, labels, statuses,
  workflow states, relations)
- `admin` — only if managing workspace-wide config (avoid)
- `app:assignable`, `app:mentionable` — agent-only, require
  `actor=app` install mode (incompatible with `admin`)

**Recommendation for the bridge:** request `read,write,issues:create,
comments:create`. The same OAuth token works for both the MCP path
(passed via Bearer) and the GraphQL fallback (passed to `@linear/sdk`
`LinearClient({ accessToken })`). No need for a separate machine-user
token. If a machine identity is wanted for audit purposes, mint a
personal API key on a dedicated bot user — Linear treats it identically
to an OAuth token for rate limiting and scopes.

## 5. Schema hierarchy & other plan-relevant facts

- **Hierarchy:** Workspace → Team → Issue (Issue belongs to a Team via
  `teamId`, required). Projects are workspace-level and *associate* with
  one or more Teams via `addTeams`/`setTeams` arrays. An Issue lives in
  a Team and *optionally* references a `projectId` and
  `projectMilestoneId`. Workspace IDs are implicit in the OAuth token
  (one token = one workspace). The bridge does not pass workspaceId
  anywhere.
- **Workflow States are team-scoped**, not workspace-scoped. Multi-team
  spec workflows need state creation per team.
- **Project Status is workspace-scoped** (statuses live on the workspace
  flow), so the bridge resolves status IDs once per workspace.
- **Pagination:** standard Relay-style `first/last/after/before` on
  every connection. Default page size 50. MCP `list_*` tools expose
  `limit`, `before`, `after` only — a curated subset.
- **Idempotency:** every create input accepts an optional `id: String`
  (UUIDv4). Pass a deterministic UUID derived from spec-kit identifiers
  to make retries safe. No separate idempotency-key header.
- **Recent breaking changes since Feb 2026:** SSE endpoint
  `mcp.linear.app/sse` is being deprecated in favour of
  `mcp.linear.app/mcp` (Streamable HTTP); errors phase in over ~2
  months from Feb 2026. April 2026 changelog added MCP support *to* the
  Linear Agent (Agent calls external MCPs) — this is orthogonal to the
  bridge and not breaking. No GraphQL schema breaking changes
  identified.

## Sources

- https://linear.app/docs/mcp
- https://linear.app/docs/mcp.md
- https://linear.app/changelog/2026-02-05-linear-mcp-for-product-management
- https://linear.app/changelog/2025-05-01-mcp
- https://linear.app/changelog/2026-04-23-linear-agent-mcp-support
- https://linear.app/developers/graphql
- https://linear.app/developers/oauth-2-0-authentication
- https://linear.app/developers/agents
- https://linear.app/developers/rate-limiting
- https://github.com/linear/linear/blob/master/packages/sdk/src/schema.graphql
  (raw schema introspected locally; line numbers cited above)
- https://blog.fiberplane.com/blog/mcp-server-analysis-linear/ (23-tool
  catalogue + design-philosophy notes)
- https://www.speakeasy.com/use-cases/mcp-governance/catalog/linear
  (31-tool count after Feb 2026 additions)

## Outstanding unknowns

- Exact MCP parameter casing (`projectMilestoneId` vs
  `project_milestone_id`) on `update_issue` — schema is camelCase, MCP
  tool args usually pass through camelCase but unconfirmed without a
  live `tools/list` call.
- Whether `create_comment` in the official MCP accepts `projectId` /
  `projectUpdateId` today, or only `issueId`. GraphQL supports it; the
  MCP wrapper may not have exposed the field yet. **One runtime probe
  resolves this** (call `tools/list` and inspect `create_comment`
  schema).
- Per-mutation sub-rate-limits are undocumented; only discoverable from
  response headers at runtime.
