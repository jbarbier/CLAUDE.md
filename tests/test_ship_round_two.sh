#!/usr/bin/env bash
# The PR review cycle, round two.
#
# Round 1 pushes the session branch. A teammate then merges something into the
# base branch. Round 2 follows the documented ritual: commit, rebase, push. The
# rebase rewrites commits that were already pushed, so a plain push MUST be
# rejected. That is why "After every task" says --force-with-lease on later
# rounds, and why "Safety" carves it out of the force-push ban.
#
# Without that carve-out the documented ritual deadlocks against the documented
# safety rule the second time anyone responds to review feedback.
set -uo pipefail
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

L=$(mktemp -d); trap 'rm -rf "$L"' EXIT
export HOME="$L/h"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
git config --global user.email julien@venicodivici.com
git config --global user.name "Julien Barbier"
git config --global init.defaultBranch main

git init -q --bare "$L/origin.git"
git init -q -b main "$L/repo"
git -C "$L/repo" commit -q --allow-empty -m init
git -C "$L/repo" remote add origin "$L/origin.git"
git -C "$L/repo" push -q -u origin main

WT="$HOME/.claude-worktrees/repo/eeee5555"
git -C "$L/repo" worktree add -q -b jbarbier/ship-test-eeee5555 "$WT" origin/main
git -C "$WT" commit -q --allow-empty -m "round 1"

echo "== round 1 =="
git -C "$WT" push -q -u origin HEAD 2>/dev/null
check "first push succeeds" "$?" "0"
PUSHED=$(git -C "$WT" rev-parse HEAD)

echo "== a teammate lands on the base branch =="
git clone -q "$L/origin.git" "$L/teammate"
git -C "$L/teammate" config user.email teammate@example.com
git -C "$L/teammate" config user.name Teammate
git -C "$L/teammate" commit -q --allow-empty -m "teammate work"
git -C "$L/teammate" push -q origin HEAD:main 2>/dev/null
check "teammate push succeeds" "$?" "0"

echo "== round 2: commit, rebase, push =="
git -C "$WT" commit -q --allow-empty -m "review feedback"
git -C "$WT" fetch -q origin
git -C "$WT" rebase origin/main >/dev/null 2>&1
check "rebase succeeds" "$?" "0"
[ "$(git -C "$WT" rev-parse HEAD)" != "$PUSHED" ] \
  && ok "rebase rewrote history that was already pushed" \
  || bad "rebase was a no-op, the test is not exercising the case"

if git -C "$WT" push -q origin HEAD 2>/dev/null; then
  bad "plain push after rebase succeeded (the --force-with-lease rule would be pointless)"
else
  ok "plain push after rebase is REJECTED, exactly as the rule warns"
fi

git -C "$WT" push -q --force-with-lease origin HEAD 2>/dev/null
check "--force-with-lease succeeds on your own session branch" "$?" "0"
check "remote now has the rebased commit" \
  "$(git -C "$L/repo" ls-remote origin jbarbier/ship-test-eeee5555 | cut -f1)" \
  "$(git -C "$WT" rev-parse HEAD)"

echo "== --force-with-lease still protects against clobbering someone else =="
# Someone pushes to the session branch behind our back; --force-with-lease must refuse.
git -C "$L/teammate" fetch -q origin
git -C "$L/teammate" switch -q -c poach origin/jbarbier/ship-test-eeee5555
git -C "$L/teammate" commit -q --allow-empty -m "someone else's commit"
git -C "$L/teammate" push -q origin HEAD:jbarbier/ship-test-eeee5555
git -C "$WT" commit -q --allow-empty -m "our next change"
if git -C "$WT" push -q --force-with-lease origin HEAD 2>/dev/null; then
  bad "--force-with-lease clobbered a commit it had never seen"
else
  ok "--force-with-lease refuses when the remote moved underneath (not a blind force)"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
