#!/usr/bin/env bash
# Gate tests for the branching rules in CLAUDE.md. Deterministic, local, free.
#   bash tests/run.sh
# Everything runs in throwaway repos under $TMPDIR with an overridden $HOME,
# so your real repos and your real ~/.gitconfig are never touched.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
RC=0
for t in test_branching_design.sh test_branching_snippets.sh test_ship_round_two.sh; do
  echo "=== $t ==="
  bash "$t" || RC=1
  echo
done
[ "$RC" -eq 0 ] && echo "ALL GREEN" || echo "FAILURES ABOVE"
exit "$RC"
