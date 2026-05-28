# Changelog

All notable changes to **spec-kit-linear** are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Nothing landed yet for v0.1.1. Add entries here as they merge._

## [0.1.0] — 2026-05-28

First public release. Mirror every spec on disk into a Linear Issue, kept in sync by spec-kit's own `after_*` hooks plus local git hooks plus a GitHub Actions webhook.

### Added — Commands

- **`/speckit.linear.install`** — interactive install ceremony. Resolves Linear Team / Project / operator UUIDs, captures operator identity via `viewer` query (FR-034), writes `.specify/extensions/linear/linear-config.yml`, registers `after_*` hooks in `.specify/extensions.yml` (FR-031), installs local git hooks (FR-033), optionally installs the GitHub Action layer with copy-paste `gh secret set LINEAR_API_TOKEN` instructions (FR-027 / FR-029). Verifies every external dependency it touches and surfaces a structured status report (FR-018b). Detects seeded-state and prompts to run seed inline (T063). Dogfood-safe install mode via `SPECKIT_LINEAR_DOGFOOD_SAFE=1` (FR-033b).
- **`/speckit.linear.seed`** — one-shot workspace setup. Creates 9 lifecycle workflow states (`Specifying`, `Clarifying`, `Planning`, `Tasking`, `Red-team`, `Implementing`, `Analyzing`, `Ready-to-merge`, `Merged`) and the `phase:*` + `task-phase:1..9` label families. Captures every UUID at creation and writes them back into `linear-config.yml.workflow_state_uuids` so renames in Linear's UI never break the bridge (FR-032). Idempotent.
- **`/speckit.linear.push`** — the reconciler. Fires automatically on every `/speckit.*` lifecycle command via auto-registered `after_*` hooks; also invokable on demand. Reconciles every `specs/NNN-feature/` directory in the consumer repo into the Linear Project. Idempotent: re-running on unchanged state produces zero churn (SC-002).
- **`/speckit.linear.status`** — read-only drift inspector. Per spec, flags mismatches between disk and Linear: lifecycle phase, current branch, last-touched timestamp, task-phase completion ratio. Surfaces the authority status (FR-025 — is the current worktree authoritative for each spec?). `--human` table or `--json`. Never writes.
- **`/speckit.linear.pull`** — read-only cross-repo unified view. `--repo` (default) shows every spec Issue in this repo's Project; `--workspace-wide` shows every spec Issue across every Project bound to the operator's team. Useful for the "what's everyone's spec status" question from any directory.

### Added — Architecture

- **Layer D (reconciler)** + **Layer E (GitHub Action webhook)** — both independently idempotent. Either alone keeps Linear converging; both together cover live commits and retroactive sync. Layer E flips Issues to `Ready-to-merge` and `Merged` in real time on PR events.
- **Workspace label** `speckit-spec:NNN` as the stable lookup key for every spec Issue (FR-004b). Duplicate-resolution: most-recent activity wins, others archived.
- **Memory block** — auto-managed markdown table on every spec Issue's description carrying current lifecycle phase, branch, worktree(s), last-touched timestamp, GitHub source link. Fully bridge-owned: rewritten on every reconcile. Operator annotations belong in Linear comments (FR-008), which the bridge never touches.
- **Local git hooks** (`post-checkout`, `post-commit`, `post-merge`) — fire the reconciler on branch switches, commits, and merges, so Linear stays in sync without re-running a spec-kit command (FR-033). No daemons, no crons, no filesystem watchers.
- **Write-authority gate** (FR-025 / FR-026) — only the worktree on a spec's feature branch may mutate that spec's Linear Issue. Other worktrees' syncs are read-only for that spec; current Linear state still surfaces for inspection.
- **Operator identity captured at install** via Linear's `viewer` query (FR-034). `assigneeId` stamped on every `issueCreate` (single-write-on-create — manual reassignment in Linear's UI persists across reconciles).
- **Fibonacci `[N]` story-point markers** on task lines (FR-035). Per-phase sum → sub-issue `estimate`; spec-level sum → spec Issue `estimate`. Tolerant: malformed markers ignored, no-marker omits `estimate` from the mutation (operator-set Linear value remains sticky). Graceful degrade when computed value exceeds the team's Linear estimation cap.
- **Agent identity stamping** (FR-036). Workspace label from the `agent:*` family (`agent:claude`, `agent:codex`) added to every Issue the bridge writes — sticky, never removed, allows kanban filtering by which AI agent worked on what. `Last reconciled by:` row in the memory block records the full model identifier + ISO timestamp.

### Added — Toolchain

- 5 bash modules under `src/`: `config.sh`, `graphql.sh`, `git_helpers.sh`, `summary.sh`, `parser.sh` — each independently unit-tested.
- Full bats matrix in CI: ubuntu × bash 4.4 + 5.2, macOS × bash 5.2 (macOS × bash 4.4 excluded — bash 4.4 source doesn't compile against Xcode 16.4 SDK; documented inline).
- Perf harness at `tests/perf/` — synthetic-fixture generator + threshold gate. N=10 cold 0.992s vs ≤30s target (30× SC-007 headroom); hot 0.840s vs ≤5s target (6× SC-008).
- Constitution v1.0.0 audit clean (7 Conform / 1 caveat / 0 Drift) — see `validation/constitution-recheck-2026-05-28.md`.
- Coverage measurement (T079) — pure-logic modules at ~80% effective coverage; GraphQL-talking modules validated end-to-end via 16 integration scenarios (gated on `RUN_INTEGRATION_TESTS=1`).

### Added — Documentation

- `README.md` in spec-kit community-extension catalog style.
- `CONTRIBUTING.md` with full lifecycle walkthrough for changes that add or amend FRs.
- `BRIEF.md` capturing the original architectural decisions from the BLOK9 planning session.
- Five validation artifacts under `validation/` feeding `/speckit-plan`'s research bundle.
- Full spec.md (36 FRs), plan.md (Constitution Check + Phase 0/1/2), tasks.md (84 tasks across 8 phases), data-model.md (Filesystem + Linear-side schemas), contracts/, quickstart.md.

### Reconcile-time behavior

- Lifecycle phase inferred entirely from filesystem state (FR-012): artifact presence ladder + task completion ratio + PR state.
- Retroactive sync converges to the right end-state in one reconcile without producing intermediate-phase artifacts in Linear's activity log (FR-014).
- 16 integration scenarios cover fresh-reconcile, idempotent-rerun, task-added, clarify-mirror, retroactive-sync, install-action, seed-fresh, seed-idempotent, seed-prompt, unseeded-halts, after-hook-fires, git-hook-fires, non-authoritative-worktree, status-staleness, pull-cross-repo.

[Unreleased]: https://github.com/ashbrener/spec-kit-linear/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ashbrener/spec-kit-linear/releases/tag/v0.1.0
