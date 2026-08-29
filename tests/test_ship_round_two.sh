#!/usr/bin/env bash
# The PR review cycle, round two, run exactly as "After every task" prescribes:
# fetch, rebase, push. The rebase rewrites commits that were already pushed, so
# a plain push is rejected.
#
# The subtle part, and the reason Safety names two flags instead of one:
# --force-with-lease compares against the remote-TRACKING ref, and the documented
# ritual runs `git fetch` first. That fetch updates the tracking ref, so the lease
# is satisfied and a teammate's commit on your branch is destroyed silently.
# --force-if-includes is the flag that actually refuses.
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
git -C "$L/repo" worktree add -q -b jbarbier/ship-eeee5555 "$WT" origin/main
git -C "$WT" commit -q --allow-empty -m "round 1"

echo "== round 1 =="
git -C "$WT" push -q -u origin HEAD 2>/dev/null
check "first push succeeds" "$?" "0"
PUSHED=$(git -C "$WT" rev-parse HEAD)

echo "== a teammate lands on the base branch =="
git clone -q "$L/origin.git" "$L/mate"
git -C "$L/mate" config user.email teammate@example.com
git -C "$L/mate" config user.name Teammate
git -C "$L/mate" commit -q --allow-empty -m "teammate work"
git -C "$L/mate" push -q origin HEAD:main 2>/dev/null
check "teammate push succeeds" "$?" "0"

echo "== round 2: the documented ritual =="
git -C "$WT" commit -q --allow-empty -m "review feedback"
git -C "$WT" fetch -q origin
git -C "$WT" rebase origin/main >/dev/null 2>&1
check "rebase succeeds" "$?" "0"
[ "$(git -C "$WT" rev-parse HEAD)" != "$PUSHED" ] \
  && ok "rebase rewrote history that was already pushed" \
  || bad "rebase was a no-op, this test is not exercising the case"
if git -C "$WT" push -q origin HEAD 2>/dev/null; then
  bad "plain push after rebase succeeded, so the whole rule would be pointless"
else
  ok "plain push after rebase is REJECTED, exactly as the rule warns"
fi
git -C "$WT" push -q --force-with-lease --force-if-includes origin HEAD 2>/dev/null
check "the documented flag pair succeeds on your own branch" "$?" "0"
check "remote now has the rebased commit" \
  "$(git -C "$L/repo" ls-remote origin jbarbier/ship-eeee5555 | cut -f1)" \
  "$(git -C "$WT" rev-parse HEAD)"

echo "== why --force-with-lease ALONE is not enough after a fetch =="
# Someone pushes to your session branch. You then run the documented sequence,
# which fetches before pushing.
git -C "$L/mate" fetch -q origin
git -C "$L/mate" switch -q -c poach origin/jbarbier/ship-eeee5555
git -C "$L/mate" commit -q --allow-empty -m "TEAMMATE COMMIT ON YOUR BRANCH"
git -C "$L/mate" push -q origin HEAD:jbarbier/ship-eeee5555
THEIRS=$(git -C "$L/mate" rev-parse HEAD)

git -C "$WT" commit -q --allow-empty -m "our next change"
git -C "$WT" fetch -q origin                     # <- the fetch that defeats the bare lease
if git -C "$WT" push -q --force-with-lease --force-if-includes origin HEAD 2>/dev/null; then
  bad "--force-if-includes allowed a push over a commit we never integrated"
else
  ok "--force-if-includes REFUSES after a blind fetch (this is the flag that saves you)"
fi
check "teammate's commit is still on the remote" \
  "$(git -C "$L/repo" ls-remote origin jbarbier/ship-eeee5555 | cut -f1)" "$THEIRS"

# And the counter-proof: the bare lease would have destroyed it.
git -C "$WT" push -q --force-with-lease origin HEAD 2>/dev/null
if [ "$(git -C "$L/repo" ls-remote origin jbarbier/ship-eeee5555 | cut -f1)" = "$THEIRS" ]; then
  bad "bare --force-with-lease refused too, so the second flag would be redundant"
else
  ok "bare --force-with-lease DESTROYED it, which is why Safety names both flags"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
