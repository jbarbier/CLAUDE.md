#!/usr/bin/env bash
# REGRESSION FIXTURE, not a recipe. This is the pre-review (v1) setup block.
# It looked right and passed the first version of the grader 7/7, but review
# found it silently broken in five ways. The grader must now FAIL it. If this
# file ever passes, the eval has lost its discriminating power and the score it
# reports is meaningless.
#
# What is wrong with it, all verified:
#   - no check that CLAUDE_CODE_SESSION_ID is set; unset means every session
#     shares one worktree, with exit code 0 and a cheerful message
#   - `git worktree add` failure is swallowed by the unconditional echo below
#   - caches the branch prefix --global, so a work handle leaks into personal repos
#   - `[ -e "$WT" ]` re-attaches to any leftover directory, not to a real worktree
SLUG=fix-login
SID=${CLAUDE_CODE_SESSION_ID:0:8}
ROOT=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
KEY=$(basename "$ROOT")-$(printf %s "$ROOT" | cksum | cut -d' ' -f1)
WT="$HOME/.claude-worktrees/$KEY/$SID"

OWNER=$(git config claude.branchPrefix)
[ -n "$OWNER" ] || OWNER=$(gh api user --jq .login 2>/dev/null)
[ -n "$OWNER" ] || OWNER=$(git config user.email | cut -d@ -f1)
git config --global claude.branchPrefix "$OWNER"

git fetch -q origin 2>/dev/null
git remote set-head -a origin >/dev/null 2>&1
BASE=$(git symbolic-ref -q --short refs/remotes/origin/HEAD)
for c in origin/main origin/master main master; do
  [ -n "$BASE" ] && break
  git rev-parse -q --verify "$c" >/dev/null && BASE=$c
done

if [ -e "$WT" ]; then echo "re-attaching to existing worktree"
else git worktree add -b "$OWNER/$SLUG-$SID" "$WT" "$BASE"; fi
echo "WORKTREE $WT"
EnterWorktree path="$WT"
