#!/usr/bin/env bats
# shellcheck shell=bats
#
# tests/integration/install_e2e_discovery.bats — spec 002 US1 + US3
# end-to-end integration tests against a LIVE Linear workspace.
#
# Gating: this file is gated on `RUN_INTEGRATION_TESTS=1` AND a valid
# `LINEAR_API_KEY`. Without both, every `@test` block early-skips.
# Matches the spec 001 `tests/integration/*.bats` convention so the
# CI matrix's `RUN_INTEGRATION_TESTS=1` row picks it up automatically
# (per T202 audit).
#
# Phase 3 status: scaffold + one US1 smoke-test placeholder gated for
# the live-network row. Phase 5 (T252..T254) layers FR-046 / FR-047 /
# FR-049 safety-guard integration tests on top of this file.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    export PROJECT_ROOT
    TEST_TMP="${BATS_TEST_TMPDIR}/work"
    mkdir -p "$TEST_TMP"
    cd "$TEST_TMP"
}

teardown() {
    :
}

@test "US1 e2e: live discovery flow resolves team + project via Linear (FR-037..FR-043)" {
    if [[ "${RUN_INTEGRATION_TESTS:-0}" != "1" ]]; then
        skip "RUN_INTEGRATION_TESTS != 1 — gated integration test"
    fi
    if [[ -z "${LINEAR_API_KEY:-}" ]]; then
        skip "LINEAR_API_KEY missing — integration test requires a live key"
    fi
    # T231 wires this against the OSH-INFRA workspace. The Phase 3 commit
    # lands the scaffold; the full piped-stdin operator-pick simulation
    # lands alongside the T269 dogfood-002 harness (Phase 6).
    skip "T231 live integration body lands with T269 dogfood-002 harness"
}
