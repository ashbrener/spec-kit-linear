# CI markdownlint failure — diagnosis & minimal fix

**Status:** read-only investigation. No repo files modified, no PR opened.

## 1. The failing run

| Field | Value |
|---|---|
| Run ID | `26542296703` |
| URL | <https://github.com/ashbrener/speckit-linear/actions/runs/26542296703> |
| Branch | `001-spec-kit-linear-bridge` |
| Event | `pull_request` |
| Conclusion | `failure` |
| Failing job | `markdownlint` (job id `78186355908`) |
| Failing step | `Run markdownlint-cli2` (step 4) |
| Job URL | <https://github.com/ashbrener/speckit-linear/actions/runs/26542296703/job/78186355908> |

All other jobs in the same run (`yamllint`, `shellcheck`, `bats (bash 5.2)`, `bats (bash 4.4)`) passed.

## 2. What actually failed (and what *didn't*)

**The lint never ran.** This is not a content failure — it's a workflow
misconfiguration. `markdownlint-cli2` was invoked with `--config` pointing
at a literal JSON string, but the CLI requires `--config` to be a *file
path* (with one of `.jsonc | .json | .yaml | .yml | .cjs | .mjs`).

The relevant lines from `.github/workflows/ci.yml`:

```yaml
npx --yes markdownlint-cli2 \
  --config '{"default": true, "MD013": false, "MD033": false, "MD041": false}' \
  "${globs[@]}"
```

…produce (verbatim from the CI log):

```
markdownlint-cli2 v0.22.1 (markdownlint v0.40.0)
Error: Unable to use configuration file
  '/home/runner/work/speckit-linear/speckit-linear/{"default": true, "MD013": false, "MD033": false, "MD041": false}';
  Configuration file should be one of the supported names
  (e.g., '.markdownlint-cli2.jsonc') or a prefix with a supported name
  (e.g., 'example.markdownlint-cli2.jsonc') or have a supported extension
  (e.g., jsonc, json, yaml, yml, cjs, mjs).
##[error]Process completed with exit code 2.
```

`markdownlint-cli2` exits with code 2 *before* enumerating any markdown,
so the CI surface shows zero rule violations today. The operator's
framing ("markdown lint step is failing") is correct, but the assumed
root cause (rule violations to disable) is downstream of the real fault.

## 3. Projected warnings — local dry-run

To forecast what CI *would* report once the config plumbing is fixed,
I ran `markdownlint-cli2 v0.22.1` locally against the same glob set
(`README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `specs/**/*.md`) with
the workflow's intended rule set (`default: true`, MD013/MD033/MD041
disabled) supplied via a temp `.markdownlint-cli2.jsonc`.

**Total warnings: 200 across 5 files.**

(The workflow also tries `commands/*.md` but that directory doesn't
exist in the repo, so it's elided by the dynamic glob builder. `README.md`,
`CHANGELOG.md`, `CONTRIBUTING.md`, and the two checklist/spec files in
`specs/001-.../` produced **zero** warnings — all 200 come from the
plan/research/data-model/quickstart artefacts.)

### 3.1 By rule

| Rule | Count | Nature | Recommended action |
|---|---|---|---|
| `MD060/table-column-style` | 164 | Stylistic — flags compact pipe tables (`\|---\|---\|`) lacking internal spaces. Tables are valid GFM, just a different style preference. | **Disable.** Spec tables use compact style consistently. |
| `MD032/blanks-around-lists` | 15 | Stylistic — list items follow heading/paragraph without blank line. False positive in `research.md` where italic *Option name* — *verdict* lines lead each subsection. | **Disable** (or fix in research.md; see §5). |
| `MD036/no-emphasis-as-heading` | 10 | Stylistic — bold `**Invariants**` used as sub-subheading inside H3 sections of `data-model.md`. Matches the spec-template convention. | **Disable.** Pattern is intentional and repo-wide. |
| `MD040/fenced-code-language` | 6 | Stylistic in this repo — fences contain CLI/program output and URLs, which are language-agnostic. | **Disable.** Adding a fake language tag is more noise than the rule prevents. |
| `MD004/ul-style` | 4 | Stylistic — three lines use `+` for a bullet instead of `-`. | **Fix** in source (trivial 4-char edits) **or** disable. |
| `MD001/heading-increment` | 1 | Mild structural — `research.md` jumps H1 → H3 at line 11. | **Fix** in source (1-line edit) **or** disable. |

### 3.2 By file

| File | Warnings | Dominant rule |
|---|---|---|
| `specs/001-spec-kit-linear-bridge/data-model.md` | 167 | MD060 (tables), MD036 (`**Invariants**`) |
| `specs/001-spec-kit-linear-bridge/research.md` | 21 | MD032 (lists), MD060, MD004, MD001 |
| `specs/001-spec-kit-linear-bridge/quickstart.md` | 6 | MD040 (untagged fences) |
| `specs/001-spec-kit-linear-bridge/spec.md` | 4 | MD060 |
| `specs/001-spec-kit-linear-bridge/plan.md` | 2 | MD004 |

`README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, and
`specs/001-.../checklists/requirements.md` were clean.

## 4. Recommended fix — **hybrid, Path A weighted**

Two things are needed; neither requires touching spec/plan/research/data-model
*content*.

### 4.1 Primary fix — make CI invoke the linter correctly

The workflow's `--config` flag cannot accept inline JSON. There are two
shapes the fix can take:

1. **Commit a config file at the repo root** and pass its path to
   `--config`. Requires editing `ci.yml` (out of scope for this report
   per task constraints), OR
2. **Commit a config file at the repo root and drop `--config` entirely**
   — `markdownlint-cli2` auto-discovers `.markdownlint-cli2.{jsonc,yaml,...}`
   in the working directory. Also requires editing `ci.yml`.

> **Important caveat:** *just* adding the config file (without editing
> `ci.yml`) will **not** make CI green. The current workflow still
> passes `--config '{...}'`, which fails before auto-discovery is
> consulted. The minimal workflow edit is one line: either change
> `--config '{...}'` to `--config .markdownlint-cli2.jsonc`, or remove
> the `--config '{...}'` line entirely. The task said "do not modify
> the workflow definition" — this is the one place that has to be
> revisited; the inline-JSON `--config` is the bug. Flag this to the
> operator before merging.

### 4.2 Drafted config — `.markdownlint-cli2.jsonc`

Drop this at the repo root. It preserves the three rule-disables the
workflow author already intended (MD013, MD033, MD041) and adds the
four additional disables warranted by the local dry-run. No spec,
plan, research, data-model, or quickstart content needs to change.

```jsonc
// .markdownlint-cli2.jsonc
//
// Repo-wide markdownlint-cli2 configuration. Consumed by the
// `markdownlint` job in .github/workflows/ci.yml.
//
// Rationale for each disabled rule lives next to the rule below;
// keep this file as the single source of truth so CI and local
// `npx markdownlint-cli2` agree.
{
  "config": {
    "default": true,

    // ----- Already intended by the workflow author -----
    // MD013: line length. Spec/plan/research narrative uses
    // hard-wrapped prose that intentionally exceeds 80 cols when a
    // sentence reads better unwrapped (e.g. URLs, code references).
    "MD013": false,
    // MD033: inline HTML. We use `<!-- ... -->` comments inside
    // spec templates for [NEEDS CLARIFICATION] sentinels and
    // template machinery. Disabling is repo policy, not laxity.
    "MD033": false,
    // MD041: first line must be top-level heading. Some artefacts
    // (CHANGELOG fragments, generated sections) legitimately start
    // with prose or H2.
    "MD041": false,

    // ----- Added based on the local dry-run on this branch -----
    // MD060: table column style. Specs use compact pipe tables
    // (`|---|---|---|`) without inner whitespace. Valid GFM,
    // consistent across the repo, 164 occurrences in data-model.md
    // alone — disabling is correct.
    "MD060": false,
    // MD036: emphasis as heading. The spec template uses bold
    // `**Invariants**` / `**Type notes**` as sub-subheadings under
    // H3 sections. Pattern is deliberate (keeps the heading tree
    // shallow for downstream TOC tools).
    "MD036": false,
    // MD040: fenced code language. Many code fences in quickstart.md
    // hold language-agnostic CLI output / URLs / log snippets.
    // Tagging them with a fake language is more harmful than the
    // rule's intent (machine-readable syntax hints).
    "MD040": false,
    // MD032: blanks-around-lists. False positives in research.md
    // where italicised *option name* — *verdict* lines anchor each
    // subsection and lists follow without an intervening blank.
    // Could also be fixed in source (see §5); disabling is the
    // zero-churn path consistent with treating spec artefacts as
    // committed lifecycle output.
    "MD032": false
  }
}
```

With this config in place AND the workflow's `--config` argument
either dropped or repointed to `.markdownlint-cli2.jsonc`, the
remaining warning count is **5** (4× MD004, 1× MD001) — all of which
fall to §5 below.

### 4.3 Alternative: stricter config

If the operator prefers to keep MD036 / MD040 / MD032 / MD004 / MD001
*enabled* and fix the sources instead, the only addition needed
beyond the workflow's current intent is `MD060: false`. The 164
MD060 hits are unambiguously stylistic and fixing them would rewrite
every table in the spec for no semantic gain.

## 5. Genuinely defective markdown (fix-in-source candidates)

If the operator wants to fix rather than disable rules **MD001** and
**MD004**, the edits are surgical. **I have not modified these files.**

| File | Line | Rule | Current | Suggested edit |
|---|---|---|---|---|
| `specs/001-spec-kit-linear-bridge/research.md` | 11 | MD001 | First heading after the `# Research …` H1 is `### …`, skipping H2 | Promote to `## …`, *or* demote subsequent levels consistently |
| `specs/001-spec-kit-linear-bridge/research.md` | 257 | MD004 | Bullet uses `+` | Change `+` → `-` |
| `specs/001-spec-kit-linear-bridge/data-model.md` | 148 | MD004 | Bullet uses `+` | Change `+` → `-` |
| `specs/001-spec-kit-linear-bridge/plan.md` | 133 | MD004 | Bullet uses `+` | Change `+` → `-` |
| `specs/001-spec-kit-linear-bridge/plan.md` | 154 | MD004 | Bullet uses `+` | Change `+` → `-` |

These are the only warnings that arguably represent real defects
versus style-rule mismatch. Even MD004 is debatable — `+`/`-`/`*`
are all valid Markdown bullet markers; the rule just enforces
consistency. The MD001 case is the strongest "fix in source"
candidate (heading hierarchy *should* increment by one).

## 6. Out of scope (read-only constraints honored)

- No source markdown files were modified.
- No `.markdownlint-cli2.jsonc` was committed.
- No edit to `.github/workflows/ci.yml`.
- No `gh pr` / `git push` / `git commit` actions taken.
- The drafted config block in §4.2 is provided as text only.

## 7. TL;DR for the operator

1. The `markdownlint` CI step is failing because `--config '<inline JSON>'`
   is not a valid argument shape for `markdownlint-cli2`. The linter
   exits before reading any markdown.
2. The minimal fix has **two parts**, both required:
   - **(a)** Commit the `.markdownlint-cli2.jsonc` drafted in §4.2 at
     the repo root.
   - **(b)** Edit `.github/workflows/ci.yml` to either drop the
     `--config '{...}'` argument (letting auto-discovery pick up the
     new file) or replace it with `--config .markdownlint-cli2.jsonc`.
3. With both in place, CI will lint successfully and emit at most 5
   residual warnings (MD001 ×1, MD004 ×4) — those are listed in §5
   if the operator wants to clean them up; otherwise add MD001 and
   MD004 to the disable list and CI is fully green.
