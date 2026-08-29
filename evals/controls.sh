#!/usr/bin/env bash
# Grader controls. Run these before trusting any eval score: they prove the
# grader still tells good answers from bad ones.
#
#   negative  : the naive "just make a branch" answer            -> must FAIL
#   regression: the pre-review v1 block that scored 7/7 once     -> must FAIL
#   positive  : the section's current setup block                -> must PASS
set -uo pipefail
R=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
RC=0

printf 'git checkout -b fix-login\n' > "$T/naive.sh"
awk '/^## Branching/,/^## The two machine spaces/' "$R/CLAUDE.md" |
  awk '/^ *```bash/{n++;if(n==1){g=1;next}} g&&/^ *```/{exit} g' > "$T/current.sh"
printf 'EnterWorktree path="$WT"\n' >> "$T/current.sh"

expect(){ # $1 = label, $2 = file, $3 = PASS|FAIL
  out=$(bash "$R/evals/grade_branching.sh" "$2" 2>&1); got=$(echo "$out" | tail -1)
  if [ "$got" = "EVAL $3" ]; then printf '  ok   %-38s -> %s\n' "$1" "$got"
  else printf '  FAIL %-38s -> %s (wanted EVAL %s)\n' "$1" "$got" "$3"
       echo "$out" | grep -E "MISS|VIOL|UNSAFE" | sed 's/^/         /'; RC=1; fi; }

expect "negative control (naive branch)"   "$T/naive.sh"                     FAIL
expect "regression control (v1 block)"     "$R/evals/fixtures/v1_answer.sh"  FAIL
expect "positive control (current block)"  "$T/current.sh"                   PASS

[ "$RC" -eq 0 ] && echo "  controls OK: the grader discriminates" \
                || echo "  CONTROLS BROKEN: eval scores are not trustworthy"
exit "$RC"
