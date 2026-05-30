# Open Design Questions — NOT RATIFIED, DO NOT IMPLEMENT

**These are unresolved discussion items. None is a spec, an FR, or a task.**
Nothing in this file is scoped for implementation. To pursue any item
here, it MUST first go through `/speckit-specify` as its own spec and
run the full lifecycle (clarify → plan → tasks → implement). The
`/speckit-*` commands and the bridge reconciler only ever act on
`specs/NNN-feature/` directories and `tasks.md` files — this document
is inert with respect to every automated path. Treat it as a parking
lot for thinking, nothing more.

Each question links to a GitHub issue where discussion happens.

---

## Q1 — Should specs map to Linear Projects instead of Issues?

**Tracking issue**: [#17](https://github.com/ashbrener/spec-kit-linear/issues/17)
**Status**: OPEN — discussion only. Recommendation leans "keep current model as default; re-evaluate as a possible spec 004 after spec 003 lands."

### Current model (ratified in spec 001)

| Filesystem | Linear |
|---|---|
| Consumer repo | **Project** |
| Spec (`specs/NNN-feature/`) | **Issue** (label `speckit-spec:NNN`) |
| Task phase (`## Phase N`) | **sub-issue** |
| Task | **checklist item** |

### Proposed alternative

| Filesystem | Linear |
|---|---|
| Consumer repo | **Team** (or unmapped) |
| Spec | **Project** |
| Task phase | **Issue** |
| Task | **sub-issue** or checklist item |

### Where spec→Project wins

- Task phases become first-class **Issues** — assignable, estimable, commentable, with their own workflow states + cycle assignment. Today a task phase is a weaker sub-issue and a task is just a checklist line (no assignee, state, or comments).
- Linear's Project-grade features light up: Project updates, milestones, target dates, progress graphs, documents. A spec — a body of work with phases — is arguably more Project-shaped than Issue-shaped.
- Scales better for large specs: a 10-phase / 80-task spec is cramped as 1 Issue + 10 sub-issues + 80 checklist lines; native as a Project with 10 Issues.

### Where the current spec→Issue model wins

- `repo → Project → Issue` is intuitive ("this repo's work, these specs").
- Cross-repo unified view is trivial — all specs are Issues, filterable by the `speckit-spec:NNN` label in one place. Specs-as-Projects turns "all specs everywhere" into a Project-list view that Linear filters less gracefully.
- **Lifecycle states map cleanly to an Issue's state machine** (Specifying → … → Merged, nine states). Linear Projects expose only a coarse status enum (Planned / Started / Completed) that cannot represent the nine lifecycle phases.
- Projects are heavier objects; hundreds of specs-as-Projects could clutter the workspace Project list.

### Possible resolution

Not necessarily either/or — a per-repo config mode (`spec_granularity: issue | project`) could offer both, but that roughly doubles the reconcile surface and the data model. Significant lift; only worth it if dogfood data shows the Issue model genuinely strains for large specs.

### Recommendation (discussion, not a decision)

Keep spec→Issue as the shipping default. The lifecycle-state-on-Issue advantage is concrete, and the founding use case is "many repos, many specs, one pane" — which spec→Issue serves directly. Re-evaluate spec→Project as a possible **spec 004** after spec 003 (drift-aware authority) ships and there is real dogfood evidence on how cramped large specs feel in practice.

---

## Q2 — `.linearrc` cascade for API-key resolution (replace per-repo `.env`)

**Tracking issue**: [#20](https://github.com/ashbrener/spec-kit-linear/issues/20)
**Status**: OPEN — discussion only. v0.2.x candidate; backward-compatible (per-repo `.env` stays as a low-precedence fallback).

### Problem

FR-037 resolves the Linear API key as: `LINEAR_API_KEY` env var → per-repo `.env` → interactive prompt. The per-repo `.env` is a **granularity mismatch** — the key is per-operator (a personal token) but `.env` stores it per-working-directory:

- **Worktrees don't share `.env`** (gitignored files are not copied into linked worktrees), so every worktree needs its own copy. Observed live: a reconcile from a worktree failed until `.env` was hand-copied in.
- Cross-spec / cross-repo propagation is brittle.

### Proposed — `.linearrc` cascade (npm `.npmrc` model)

Resolution order, highest → lowest precedence:

| Tier | Source | Role |
|---|---|---|
| 1 | `LINEAR_API_KEY` env var | CI / ephemeral overrides (already supported) |
| 2 | project `./.linearrc` (gitignored) | per-repo **non-secret** overrides (team/project hints, on-drift default). NOT the key — putting the secret here reproduces the `.env` worktree problem. |
| 3 | user `~/.linearrc` or `$XDG_CONFIG_HOME/spec-kit-linear/linearrc` | **operator-global; recommended home for the API key.** Inherited by every repo/worktree/spec. |
| 4 | keychain command (configurable `key_command`) | `security find-generic-password …` / `op read …`. Most secure; no plaintext at rest. |

The secret lives at tier 3 or 4 (operator-global), which solves worktree + cross-spec propagation. Tier 2 mirrors how npm's project `.npmrc` overrides settings while the auth token lives in `~/.npmrc`.

### Constitution fit

Principle VI (OAuth-First, Keys-At-The-Edges): the key only ever lives at the edges (env / user-rc / keychain), never committed, resolved once per operator. The keychain tier is the strongest expression of "keys at the edges."

### Immediate workaround (no code today)

The env var is already tier 1, so operators can `export LINEAR_API_KEY` in their shell rc (keychain-backed if desired) right now — every repo/worktree/spec inherits it. The `.linearrc` cascade is the ergonomic upgrade that removes the shell-rc dependency.
