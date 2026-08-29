#!/usr/bin/env bash
# Verifies the "worktree per session, branch per task" recipe that is about to
# be written into CLAUDE.md. Every assertion here maps to a claim in that text.
set -uo pipefail

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

LAB=$(mktemp -d)
trap 'rm -rf "$LAB"' EXIT
export HOME="$LAB/home"; mkdir -p "$HOME"
WTROOT="$HOME/.claude-worktrees"

# ---------------------------------------------------------------- the recipe
# This function is the exact logic that goes in CLAUDE.md. It must be
# idempotent: running it twice for the same session is a no-op that re-attaches.
session_worktree() {
  # $1 = session id, $2 = task slug. Echoes the worktree path.
  local sid=${1:0:8} slug=$2 repo wt base owner branch
  repo=$(repo_key)
  wt="$HOME/.claude-worktrees/$repo/$sid"
  owner=$(git config user.email | cut -d@ -f1 | tr -c 'a-z0-9-' '-' | sed 's/-*$//')
  branch="$owner/$slug-$sid"

  if git worktree list --porcelain | grep -qx "worktree $wt"; then
    # Session already has its worktree. New task = new branch inside it.
    if ! git -C "$wt" show-ref --verify --quiet "refs/heads/$branch"; then
      base=$(resolve_base)
      git -C "$wt" switch -q -c "$branch" "$base" || return 1
    fi
    echo "$wt"; return 0
  fi

  base=$(resolve_base)
  git worktree add -q -b "$branch" "$wt" "$base" || return 1
  echo "$wt"
}

# Path of the shared checkout, correct whether called from it or from a worktree,
# and safe on paths containing spaces.
repo_root() { dirname "$(git rev-parse --path-format=absolute --git-common-dir)"; }
# Worktree key: basename alone collides when two repos share a directory name.
repo_key() { local r; r=$(repo_root); printf '%s-%s' "$(basename "$r")" \
  "$(printf %s "$r" | cksum | cut -d' ' -f1)"; }

resolve_base() {
  git fetch -q origin 2>/dev/null
  if   b=$(git symbolic-ref -q --short refs/remotes/origin/HEAD); then echo "$b"
  elif git rev-parse -q --verify origin/main >/dev/null;   then echo origin/main
  elif git rev-parse -q --verify origin/master >/dev/null; then echo origin/master
  elif git rev-parse -q --verify main >/dev/null;          then echo main
  else echo master
  fi
}

# ------------------------------------------------------------------- fixture
mk_repo() {
  local up="$LAB/origin.git" wc="$LAB/shared"
  git init -q --bare "$up"
  git init -q -b main "$wc"
  git -C "$wc" config user.email julien@venicodivici.com
  git -C "$wc" config user.name "Julien Barbier"
  echo base > "$wc/file.txt"
  git -C "$wc" add -A && git -C "$wc" commit -qm init
  git -C "$wc" remote add origin "$up"
  git -C "$wc" push -q -u origin main
  git -C "$wc" remote set-head origin -a >/dev/null 2>&1
  echo "$wc"
}

SHARED=$(mk_repo)
cd "$SHARED" || exit 1
A=aaaa1111-0000-0000-0000-000000000000
B=bbbb2222-0000-0000-0000-000000000000

echo "== 1. two sessions get two worktrees =="
WA=$(session_worktree "$A" fix-login)
WB=$(session_worktree "$B" add-export)
SKEY=$(cd "$SHARED" && repo_key)
check "session A worktree path" "$WA" "$WTROOT/$SKEY/aaaa1111"
check "session B worktree path" "$WB" "$WTROOT/$SKEY/bbbb2222"
[ "$WA" != "$WB" ] && ok "worktrees are distinct" || bad "worktrees collided"
check "A branch"   "$(git -C "$WA" rev-parse --abbrev-ref HEAD)" "julien/fix-login-aaaa1111"
check "B branch"   "$(git -C "$WB" rev-parse --abbrev-ref HEAD)" "julien/add-export-bbbb2222"
check "owner slug from git email" "$(git config user.email | cut -d@ -f1)" "julien"

echo "== 2. THE core claim: a branch switch in one session moves nobody else =="
git -C "$WA" switch -q -c julien/second-task-aaaa1111
check "A moved"            "$(git -C "$WA" rev-parse --abbrev-ref HEAD)" "julien/second-task-aaaa1111"
check "B did NOT move"     "$(git -C "$WB" rev-parse --abbrev-ref HEAD)" "julien/add-export-bbbb2222"
check "shared checkout still on main" "$(git -C "$SHARED" rev-parse --abbrev-ref HEAD)" "main"

echo "== 3. idempotent re-attach (session resumes / rule re-read) =="
WA2=$(session_worktree "$A" fix-login)
check "same path returned"  "$WA2" "$WA"
check "no duplicate worktrees" "$(git worktree list | wc -l)" "3"

echo "== 4. same session, second task = new branch in the SAME worktree =="
WA3=$(session_worktree "$A" third-task)
check "path unchanged"     "$WA3" "$WA"
check "branch switched"    "$(git -C "$WA" rev-parse --abbrev-ref HEAD)" "julien/third-task-aaaa1111"
check "still 3 worktrees"  "$(git worktree list | wc -l)" "3"

echo "== 5. git structurally refuses to share a branch across worktrees =="
if git -C "$WB" switch -q julien/third-task-aaaa1111 2>/dev/null; then
  bad "git allowed two worktrees on one branch"
else
  ok "git refused the double checkout (isolation enforced by git, not by prose)"
fi

echo "== 6. dirty shared checkout does not block worktree creation =="
echo dirty > "$SHARED/uncommitted.txt"
C=cccc3333-0000-0000-0000-000000000000
if WC_=$(session_worktree "$C" hotfix); then
  ok "worktree created while shared checkout was dirty"
  check "C branch" "$(git -C "$WC_" rev-parse --abbrev-ref HEAD)" "julien/hotfix-cccc3333"
else
  bad "dirty shared checkout blocked worktree creation"
fi
check "shared dirty file untouched" "$(cat "$SHARED/uncommitted.txt")" "dirty"
rm -f "$SHARED/uncommitted.txt"

echo "== 7. work is isolated on disk =="
echo "session A edit" > "$WA/file.txt"
check "B file untouched"      "$(cat "$WB/file.txt")" "base"
check "shared file untouched" "$(cat "$SHARED/file.txt")" "base"

echo "== 8. branch pushes and is visible to the team =="
git -C "$WA" add -A && git -C "$WA" commit -qm "session A work"
git -C "$WA" push -q -u origin HEAD 2>/dev/null
if git -C "$SHARED" ls-remote --heads origin julien/third-task-aaaa1111 | grep -q .; then
  ok "branch reached origin"
else
  bad "branch did not reach origin"
fi
check "main on origin untouched" \
  "$(git -C "$SHARED" rev-parse origin/main)" "$(git -C "$SHARED" rev-parse main)"

echo "== 9. cleanup removes the worktree without touching the branch =="
git -C "$SHARED" worktree remove --force "$WB"
check "worktree count after remove" "$(git -C "$SHARED" worktree list | wc -l)" "3"
if git -C "$SHARED" show-ref --verify --quiet refs/heads/julien/add-export-bbbb2222; then
  ok "branch survived worktree removal"
else
  bad "branch was destroyed with the worktree"
fi

echo "== 10. base ref resolution picks the default branch, not local HEAD =="
git -C "$WA" commit -q --allow-empty -m "drift on A"
D=dddd4444-0000-0000-0000-000000000000
WD=$(cd "$SHARED" && session_worktree "$D" from-main)
check "new session branched from origin/main" \
  "$(git -C "$WD" rev-parse HEAD)" "$(git -C "$SHARED" rev-parse origin/main)"

echo "== 11. a worktree INSIDE the repo dirties git status unless ignored =="
git -C "$SHARED" worktree add -q -b nested "$SHARED/.claude/worktrees/nested" origin/main
NESTED_STATUS=$(git -C "$SHARED" status --short --untracked-files=normal)
if echo "$NESTED_STATUS" | grep -q '\.claude'; then
  ok "confirmed: .claude/worktrees shows as untracked (needs a .gitignore entry)"
else
  bad "expected .claude to appear untracked, got: '$NESTED_STATUS'"
fi
printf '.claude/\n' > "$SHARED/.gitignore"
check "ignoring .claude/ cleans it up" \
  "$(git -C "$SHARED" status --short --untracked-files=normal | grep -c '\.claude')" "0"
rm -f "$SHARED/.gitignore"
git -C "$SHARED" worktree remove --force "$SHARED/.claude/worktrees/nested"

echo "== 12. a worktree OUTSIDE the repo never dirties git status =="
check "shared checkout clean with 2 external worktrees" \
  "$(git -C "$SHARED" status --porcelain --untracked-files=all | wc -l)" "0"

echo "== 13. the guard: am I in my own worktree or the shared checkout? =="
in_own_worktree() { # $1 = session id; exits 0 only inside this session's worktree
  local sid=${1:0:8}
  local want; want=$(cd "$HOME/.claude-worktrees/$(repo_key)/$sid" 2>/dev/null && pwd -P)
  [ -n "$want" ] && [ "$(git rev-parse --show-toplevel)" = "$want" ]
}
if (cd "$WA" && in_own_worktree "$A"); then ok "guard passes inside session A's worktree"
else bad "guard failed inside session A's worktree"; fi
if (cd "$SHARED" && in_own_worktree "$A"); then bad "guard wrongly passed in shared checkout"
else ok "guard trips in the shared checkout"; fi
if (cd "$WA" && in_own_worktree "$B"); then bad "guard wrongly passed in another session's worktree"
else ok "guard trips in another session's worktree"; fi

echo "== 14. branch prefix resolution (email local-part is NOT trustworthy) =="
# Real case found on this machine: user.email=write0@gmail.com but the GitHub
# login teammates actually see is 'jbarbier'. Resolve once, cache in git config.
resolve_prefix() {
  local p
  if p=$(git config claude.branchPrefix); then echo "$p"; return 0; fi
  p=$(gh api user --jq .login 2>/dev/null) || p=$(git config user.email | cut -d@ -f1)
  git config claude.branchPrefix "$p"
  echo "$p"
}
cd "$SHARED" || exit 1
git config --unset claude.branchPrefix 2>/dev/null
GH_STUB="$LAB/bin"; mkdir -p "$GH_STUB"
printf '#!/bin/sh\necho jbarbier\n' > "$GH_STUB/gh"; chmod +x "$GH_STUB/gh"
WITH_GH=$(export PATH="$GH_STUB:$PATH"; resolve_prefix)
check "falls back to gh login, not email" "$WITH_GH" "jbarbier"
check "resolved value is cached in git config" "$(git config claude.branchPrefix)" "jbarbier"
git config claude.branchPrefix julien
check "explicit override wins over gh" "$(export PATH="$GH_STUB:$PATH"; resolve_prefix)" "julien"
git config --unset claude.branchPrefix
NO_GH="$LAB/nogh"; mkdir -p "$NO_GH"
printf '#!/bin/sh\nexit 1\n' > "$NO_GH/gh"; chmod +x "$NO_GH/gh"
NOGH_OUT=$(export PATH="$NO_GH:$PATH"; resolve_prefix)
check "falls back to email local-part when gh is absent" "$NOGH_OUT" "julien"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
