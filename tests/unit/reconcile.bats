#!/usr/bin/env bats
# tests/unit/reconcile.bats — unit tests for src/reconcile.sh resolver helpers
#
# Scope: pure-local resolvers that don't need Linear (the bulk of
# reconcile.sh's wire-level logic is covered by tests/integration/us1-*
# suites, which mock the GraphQL transport). This file targets FR-036's
# agent identity resolver — env-var precedence + family mapping — because
# the behaviour is small, deterministic, and stable enough to lock with
# unit tests rather than full reconcile fixtures.
#
# Compatible with bats-core 1.11.0.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

# Helper: run `_resolve_running_agent` inside a clean shell with a
# specific env-var configuration and echo the resolver's verdict in a
# parseable form. Suppresses the reconcile::log audit-line emitted on
# first call so the test output stays focused on the resolver output.
#
# Usage:
#   resolve_with_env [VAR=VALUE [VAR=VALUE …]]
# Prints: family=<...> model=<...>
#
# We splat the VAR=VALUE pairs into the bash invocation's environment
# via leading prelude rather than `env` so spaces inside VALUE survive
# (`env -i FOO='a b' bash -c …` works; concatenating `export FOO=a b`
# into a heredoc breaks on the space). Cleaner: use `eval` of a single
# pre-quoted setter list per pair, which printf %q quotes safely.
resolve_with_env() {
    local prelude="unset CLAUDE_CODE_MODEL CODEX_MODEL AGENT_NAME"
    local kv key value q
    for kv in "$@"; do
        # Split on the FIRST `=`; preserve everything after as the value
        # so values containing `=` round-trip cleanly.
        key="${kv%%=*}"
        value="${kv#*=}"
        printf -v q '%q' "$value"
        prelude+="; export ${key}=${q}"
    done

    bash -c "
        ${prelude}
        # Reconcile sources config + graphql + summary; isolate the resolver
        # from the rest by stubbing the log function before sourcing.
        source '${RECONCILE_SH}' 2>/dev/null
        # Suppress the audit log so test output is clean.
        reconcile::log() { :; }
        reconcile::_resolve_running_agent
        printf 'family=%s model=%s\n' \"\$_RECONCILE_AGENT_FAMILY\" \"\$_RECONCILE_AGENT_MODEL\"
    "
}

# ---------------------------------------------------------------------------
# CLAUDE_CODE_MODEL → claude family
# ---------------------------------------------------------------------------

@test "FR-036: CLAUDE_CODE_MODEL resolves to family=claude, model preserved" {
    run resolve_with_env "CLAUDE_CODE_MODEL=claude-opus-4-7"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"family=claude model=claude-opus-4-7"* ]]
}

@test "FR-036: CLAUDE_CODE_MODEL with case quirks still maps to claude family" {
    # Case-insensitive family mapping — the family compare is lowercased,
    # but the model string preserves operator-visible casing.
    run resolve_with_env "CLAUDE_CODE_MODEL=Claude-Sonnet-4-5"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"family=claude model=Claude-Sonnet-4-5"* ]]
}

# ---------------------------------------------------------------------------
# CODEX_MODEL / gpt-* → codex family
# ---------------------------------------------------------------------------

@test "FR-036: CODEX_MODEL resolves to family=codex" {
    run resolve_with_env "CODEX_MODEL=codex-1.0"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"family=codex model=codex-1.0"* ]]
}

@test "FR-036: CODEX_MODEL with gpt-* value still maps to codex family" {
    # Codex hosts surface their underlying GPT-* model IDs verbatim. The
    # family resolver collapses both `codex` and `gpt` prefixes to `codex`.
    run resolve_with_env "CODEX_MODEL=gpt-5.4-preview"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"family=codex model=gpt-5.4-preview"* ]]
}

# ---------------------------------------------------------------------------
# AGENT_NAME → lowercased first-word family
# ---------------------------------------------------------------------------

@test "FR-036: AGENT_NAME resolves to family=lowercased-first-word" {
    run resolve_with_env "AGENT_NAME=Gemini 2.5 Pro"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"family=gemini model=Gemini 2.5 Pro"* ]]
}

@test "FR-036: AGENT_NAME with dash-separated host name splits on the dash" {
    run resolve_with_env "AGENT_NAME=cursor-tab"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"family=cursor model=cursor-tab"* ]]
}

# ---------------------------------------------------------------------------
# Env-var precedence: CLAUDE_CODE_MODEL > CODEX_MODEL > AGENT_NAME
# ---------------------------------------------------------------------------

@test "FR-036: CLAUDE_CODE_MODEL wins over CODEX_MODEL and AGENT_NAME" {
    run resolve_with_env \
        "CLAUDE_CODE_MODEL=claude-opus-4-7" \
        "CODEX_MODEL=gpt-5.4" \
        "AGENT_NAME=cursor"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"family=claude model=claude-opus-4-7"* ]]
}

@test "FR-036: CODEX_MODEL wins over AGENT_NAME when CLAUDE_CODE_MODEL is unset" {
    run resolve_with_env \
        "CODEX_MODEL=codex-1.0" \
        "AGENT_NAME=cursor"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"family=codex model=codex-1.0"* ]]
}

# ---------------------------------------------------------------------------
# All three empty → graceful skip (empty family + empty model)
# ---------------------------------------------------------------------------

@test "FR-036: all env vars empty returns empty family + empty model" {
    run resolve_with_env
    [ "${status}" -eq 0 ]
    # Both halves explicitly empty so the caller's `[[ -n "$x" ]]` guard
    # uniformly skips the agent-label stamp AND the memory-block row.
    [[ "${output}" == *"family= model="* ]]
}
