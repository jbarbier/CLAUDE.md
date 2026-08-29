#!/usr/bin/env bash
# Periodic eval for the branching rules: does a model that reads ONLY the
# "Branching" section produce the right commands cold?
#
# Latent half: an agent reads the section and writes the commands it would run
#   before its first edit (scenario: shared repo, a teammate's session already
#   running in it, task slug "fix-login").
# Deterministic half: this script grades that output. Same input, same verdict.
#
#   bash evals/grade_branching.sh <answer.sh>
#
# Pass threshold: 6/7 must-haves, and ZERO of the must-nots.
set -uo pipefail
A=${1:?usage: grade_branching.sh /path/to/answer.sh}
[ -f "$A" ] || { echo "no answer file at $A"; exit 1; }
T=$(tr -d '\r' < "$A")

HIT=0; MISS=0; VIOL=0
must() {  # $1 = label, $2 = extended regex
  if echo "$T" | grep -qE "$2"; then HIT=$((HIT+1)); printf '  hit   %s\n' "$1"
  else MISS=$((MISS+1)); printf '  MISS  %s\n' "$1"; fi
}
never() { # $1 = label, $2 = extended regex that must NOT appear
  if echo "$T" | grep -qE "$2"; then VIOL=$((VIOL+1)); printf '  VIOL  %s\n' "$1"
  else printf '  clean %s\n' "$1"; fi
}

echo "must-haves:"
must "creates a git worktree"                 'git worktree add'
must "keys the path on the session id"        'CLAUDE_CODE_SESSION_ID'
must "worktree lives outside the repo"        '(\$HOME|~)/\.claude-worktrees'
must "branch carries the task slug"           'fix-login'
must "branch prefix is not hardcoded"         'claude\.branchPrefix|gh api user|user\.email'
must "resolves the remote default branch"     'refs/remotes/origin/HEAD'
must "moves the session into the worktree"    'EnterWorktree|cd .*(WT|worktrees)'

echo "must-nots:"
never "no bare branch in the shared checkout" '^[[:space:]]*git (checkout|switch) -[bc][^"]*$'
never "does not commit to main"               'git (commit|push).*(main|master)([[:space:]]|$)'
never "no blind force-push"                   'push [^|]*--force([[:space:]]|$)'
never "does not hardcode a base branch guess" 'BASE=(origin/)?(main|master)([[:space:]]|$)'

echo
echo "hits: $HIT   misses: $MISS   violations: $VIOL"
if [ "$HIT" -ge 6 ] && [ "$VIOL" -eq 0 ]; then echo "EVAL PASS"; exit 0
else echo "EVAL FAIL"; exit 1; fi
