#!/usr/bin/env bats
# =============================================================================
# tests/unit/drift_disposition.bats — spec 003 Phase 2 arg-parse + summary
#
# Covers the Phase-2 arg-parse + summary-plumbing foundation (no write path):
#   * --on-drift=abort|proceed parsing into ARG_ON_DRIFT (T307)
#   * --on-drift bad value → usage error at parse time (T307 / plan A11)
#   * --retroactive deprecation INFO row, exactly once (T308 / FR-061)
#   * summary.sh `info` event type → top-of-summary INFO line (T309)
#
# Disposition WIRING (the prompt, the abort skip, the proceed-and-warn write)
# is US2/US3 (T334/T343/T344) and is NOT exercised here — Phase 2 only lands
# the pure arg-parse + summary primitives.
# =============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
RECONCILE_SH="${REPO_ROOT}/src/reconcile.sh"
SUMMARY_SH="${REPO_ROOT}/src/summary.sh"

# Run reconcile::parse_args in an isolated subshell with the given args and
# echo the resolved ARG_ON_DRIFT / ARG_RETROACTIVE. We stop right after
# parse_args so no config load or network fires.
_parse() {
  bash -c '
    set +e
    source "'"$RECONCILE_SH"'" 2>/dev/null
    reconcile::parse_args "$@"
    printf "on_drift=%s retroactive=%s spec=%s all=%s\n" \
      "$ARG_ON_DRIFT" "$ARG_RETROACTIVE" "$ARG_SPEC" "$ARG_ALL"
  ' _ "$@"
}

# -----------------------------------------------------------------------------
# --on-drift parsing (T307 / FR-056 / plan A11)
# -----------------------------------------------------------------------------

@test "--on-drift=abort parses into ARG_ON_DRIFT" {
  run _parse --all --on-drift=abort
  [ "$status" -eq 0 ]
  [[ "$output" == *"on_drift=abort"* ]]
}

@test "--on-drift=proceed parses into ARG_ON_DRIFT" {
  run _parse --all --on-drift=proceed
  [ "$status" -eq 0 ]
  [[ "$output" == *"on_drift=proceed"* ]]
}

@test "--on-drift space-separated form parses" {
  run _parse --all --on-drift abort
  [ "$status" -eq 0 ]
  [[ "$output" == *"on_drift=abort"* ]]
}

@test "--on-drift omitted leaves ARG_ON_DRIFT empty (proceed-and-warn default)" {
  run _parse --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"on_drift= "* ]]
}

@test "--on-drift with an unrecognised value is a usage error at parse time" {
  run _parse --all --on-drift=maybe
  [ "$status" -eq 2 ]
  [[ "$output" == *"--on-drift value must be abort or proceed"* ]]
}

@test "--on-drift with a missing value is a usage error" {
  run _parse --all --on-drift
  [ "$status" -eq 2 ]
  [[ "$output" == *"--on-drift requires a value"* ]]
}

# -----------------------------------------------------------------------------
# --retroactive deprecation (T308 / FR-061)
# -----------------------------------------------------------------------------

@test "--retroactive still parses (deprecated no-op) and implies --all" {
  run _parse --retroactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"retroactive=1"* ]]
  [[ "$output" == *"all=1"* ]]
}

@test "--retroactive sets no disposition global (no behavioral coupling)" {
  run _parse --retroactive
  [ "$status" -eq 0 ]
  # ARG_ON_DRIFT stays empty — --retroactive is purely a deprecation marker.
  [[ "$output" == *"on_drift= "* ]]
}

# -----------------------------------------------------------------------------
# summary.sh `info` event type → top-of-summary INFO line (T309)
# -----------------------------------------------------------------------------

@test "summary: info event renders as a top-of-summary INFO line above counters" {
  run bash -c '
    source "'"$SUMMARY_SH"'"
    summary::start "title-line"
    summary::add info "--retroactive is deprecated and now the default"
    summary::add created "x"
    summary::emit 2>&1 1>/dev/null
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO  --retroactive is deprecated and now the default"* ]]
  # The INFO line precedes the Created counter row (top-of-summary placement).
  local info_pos created_pos
  info_pos="$(printf '%s\n' "$output" | grep -n 'INFO ' | head -1 | cut -d: -f1)"
  created_pos="$(printf '%s\n' "$output" | grep -n 'Created:' | head -1 | cut -d: -f1)"
  [ "$info_pos" -lt "$created_pos" ]
}

@test "summary: info increments its own counter, not warned" {
  run bash -c '
    source "'"$SUMMARY_SH"'"
    summary::start ""
    summary::add info "note"
    printf "info=%s warned=%s\n" "$(summary::count info)" "$(summary::count warned)"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"info=1 warned=0"* ]]
}

@test "summary: a clean run with no info emits no INFO line" {
  run bash -c '
    source "'"$SUMMARY_SH"'"
    summary::start ""
    summary::add created "x"
    summary::emit 2>&1 1>/dev/null
  '
  [ "$status" -eq 0 ]
  [[ "$output" != *"INFO "* ]]
}
