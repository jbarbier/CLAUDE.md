#!/usr/bin/env bash
# Runs the shell snippets EXACTLY as they appear in the "Branching" section of
# CLAUDE.md, extracted from the markdown rather than retyped, so the thing under
# test is literally the thing a reader copies.
#
# Every case below is a defect that was actually found in review, not a
# hypothetical. If you change the section, run this.
set -uo pipefail
DOC=${1:-"$(cd "$(dirname "$0")/.." && pwd)/CLAUDE.md"}
[ -f "$DOC" ] || { echo "no CLAUDE.md at $DOC"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

LAB=$(mktemp -d); trap 'rm -rf "$LAB"' EXIT
export HOME="$LAB/home"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"      # never touch the real one
export PATH="$LAB/bin:$PATH"; mkdir -p "$LAB/bin"
nogh(){ printf '#!/bin/sh\nexit 1\n' > "$LAB/bin/gh"; chmod +x "$LAB/bin/gh"; }
nogh
git config --global user.email jbarbier@example.com
git config --global user.name "Julien Barbier"
git config --global init.defaultBranch main

extract(){ awk -v want="$1" '
    /^## Branching/ {inSec=1}
    inSec && /^## The two machine spaces/ {exit}
    inSec && /^ *```bash/ {n++; if(n==want){grab=1; next}}
    grab && /^ *```/ {exit}
    grab {sub(/^  /,""); print}' "$DOC"; }
SETUP=$(extract 1); SECOND=$(extract 2); GUARD=$(extract 3); SWEEP=$(extract 4)

mkrepo(){ # $1 = path, $2 = default branch. Echoes nothing; creates repo + origin.
  git init -q --bare "$1.git"
  git init -q -b "$2" "$1"
  git -C "$1" commit -q --allow-empty -m init
  git -C "$1" remote add origin "$1.git"
  git -C "$1" push -q -u origin "$2"; }
key(){ printf '%s-%s' "$(basename "$1")" "$(printf %s "$1" | cksum | cut -d' ' -f1)"; }
# A fresh global config that can still author commits, but carries no cached
# claude.branchPrefix. $1 = file, $2 = user.email to use.
freshglobal(){ export GIT_CONFIG_GLOBAL="$1"; : > "$1"
  git config --global user.name "Julien Barbier"
  git config --global user.email "$2"
  git config --global init.defaultBranch main; }
SID=1f3b76a3

echo "== 0. every shipped block defines the variables it reads =="
i=0
for blk in "$SETUP" "$SECOND" "$GUARD" "$SWEEP"; do
  i=$((i+1)); [ -n "$blk" ] || { bad "block $i empty (extraction broke)"; continue; }
  leak=""
  for v in WT OWNER BASE SID ROOT KEY SLUG WANT; do
    echo "$blk" | grep -q "\$$v" && ! echo "$blk" | grep -qE "^ *$v=" && leak="$leak \$$v"
  done
  [ -z "$leak" ] && ok "block $i is self-contained" || bad "block $i reads undefined:$leak"
done
echo "$SETUP" | grep -q '<task-slug>' && bad "setup still has a <placeholder> mid-block" \
                                      || ok "no unexplained placeholder in the setup block"

echo "== 1. setup runs verbatim; shared checkout is left alone =="
mkrepo "$LAB/shared" main
cd "$LAB/shared" || exit 1
git switch -q -c someone-elses-wip; git commit -q --allow-empty -m wip
git remote set-head origin -a >/dev/null 2>&1
export CLAUDE_CODE_SESSION_ID=1f3b76a3-369f-4f9a-a363-99e5be44befb
WT="$HOME/.claude-worktrees/$(key "$LAB/shared")/$SID"
OUT=$(bash -c "$SETUP" 2>&1); RC=$?
check "setup exits clean" "$RC" "0"
[ "$RC" -eq 0 ] || echo "$OUT"
check "worktree created where the guard will look" "$(git -C "$WT" rev-parse --show-toplevel 2>/dev/null)" "$(cd "$WT" 2>/dev/null && pwd -P)"
check "branch name" "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" "jbarbier/fix-login-$SID"
check "based on origin default, not the wip branch" \
  "$(git -C "$WT" rev-parse HEAD)" "$(git rev-parse origin/main)"
check "shared checkout not moved" "$(git branch --show-current)" "someone-elses-wip"
echo "$OUT" | grep -q "^WORKTREE " && ok "prints the worktree path for the EnterWorktree call" \
                                   || bad "did not print the WORKTREE path"

echo "== 2. resume: same slug AND different slug both re-attach, no dangling branch =="
B1=$(git branch --list | wc -l)
R1=$(bash -c "$SETUP" 2>&1); check "re-run exits clean" "$?" "0"
R2=$(bash -c "$(echo "$SETUP" | sed 's/^SLUG=fix-login/SLUG=some-other-task/')" 2>&1)
check "re-run with a DIFFERENT slug exits clean" "$?" "0"
echo "$R2" | grep -q "re-attaching" && ok "different slug re-attaches" || bad "got: $R2"
check "no branches created by the two re-runs" "$(git branch --list | wc -l)" "$B1"
check "still exactly one session worktree" "$(git worktree list | wc -l)" "2"

echo "== 3. guard survives a symlinked \$HOME (the false-alarm bug) =="
mkdir -p "$LAB/realhome"; ln -s "$LAB/realhome" "$LAB/linkhome"
G=$(HOME="$LAB/linkhome" bash -c '
  mkdir -p "$HOME/.claude-worktrees"; true')
REAL="$LAB/realhome"; LINK="$LAB/linkhome"
mkrepo "$LAB/symrepo" main
cd "$LAB/symrepo" || exit 1
git remote set-head origin -a >/dev/null 2>&1
SYMOUT=$(HOME="$LINK" bash -c "$SETUP" 2>&1); SRC=$?
check "setup works with a symlinked HOME" "$SRC" "0"
GOUT=$(cd "$LINK/.claude-worktrees/$(key "$LAB/symrepo")/$SID" 2>/dev/null && HOME="$LINK" bash -c "$GUARD" 2>&1)
check "guard does NOT cry wolf under a symlinked HOME" "$GOUT" ""
GOUT2=$(cd "$REAL/.claude-worktrees/$(key "$LAB/symrepo")/$SID" 2>/dev/null && HOME="$LINK" bash -c "$GUARD" 2>&1)
check "guard also silent when reached via the real path" "$GOUT2" ""

echo "== 4. guard still fires where it should =="
cd "$LAB/shared" || exit 1
bash -c "$GUARD" 2>&1 | grep -q "WRONG TREE" && ok "fires in the shared checkout" \
                                             || bad "silent in the shared checkout"
git worktree add -q -b other/task-bbbb "$HOME/.claude-worktrees/$(key "$LAB/shared")/bbbbbbbb" origin/main
GO=$(cd "$HOME/.claude-worktrees/$(key "$LAB/shared")/bbbbbbbb" && bash -c "$GUARD" 2>&1)
echo "$GO" | grep -q "WRONG TREE" && ok "fires in another session's worktree" \
                                  || bad "silent in another session's worktree"

echo "== 5. repo path containing a space =="
mkdir -p "$LAB/my app"
mkrepo "$LAB/my app/proj" main
cd "$LAB/my app/proj" || exit 1
git remote set-head origin -a >/dev/null 2>&1
SPOUT=$(bash -c "$SETUP" 2>&1); check "setup exits clean with a space in the path" "$?" "0"
[ -d "$HOME/.claude-worktrees/$(key "$LAB/my app/proj")/$SID" ] \
  && ok "worktree path kept the whole repo name" || { bad "path was truncated at the space"; echo "$SPOUT"; }

echo "== 6. repo whose default branch is master, with origin/HEAD unset =="
mkrepo "$LAB/oldrepo" master
cd "$LAB/oldrepo" || exit 1
git remote set-head origin -d >/dev/null 2>&1        # simulate init+remote add
MOUT=$(bash -c "$SETUP" 2>&1); MRC=$?
check "setup exits clean on a master repo" "$MRC" "0"
[ "$MRC" -eq 0 ] || echo "    $MOUT"
check "master worktree is on its branch" \
  "$(git -C "$HOME/.claude-worktrees/$(key "$LAB/oldrepo")/$SID" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
  "jbarbier/fix-login-$SID"

echo "== 7. an unresolvable owner must NOT poison the global config =="
freshglobal "$LAB/noowner.gitconfig" jbarbier@example.com
mkrepo "$LAB/noowner" main
cd "$LAB/noowner" || exit 1
git config user.email ""                      # nothing resolvable: no prefix, no gh, no email
git remote set-head origin -a >/dev/null 2>&1
NOUT=$(bash -c "$SETUP" 2>&1); NRC=$?
[ "$NRC" -ne 0 ] && ok "setup refuses instead of building a broken branch name" \
                 || bad "setup continued with an empty owner"
echo "$NOUT" | grep -q "claude.branchPrefix" && ok "tells you how to fix it" || bad "no guidance: $NOUT"
CACHED=$(git config --global claude.branchPrefix)
[ -z "$CACHED" ] && ok "nothing was cached globally" || bad "cached a bad prefix: '$CACHED'"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"

echo "== 8. two different repos sharing a basename do not collide =="
mkdir -p "$LAB/x" "$LAB/y"; mkrepo "$LAB/x/proj" main; mkrepo "$LAB/y/proj" main
cd "$LAB/x/proj" || exit 1; git remote set-head origin -a >/dev/null 2>&1
bash -c "$SETUP" >/dev/null 2>&1
cd "$LAB/y/proj" || exit 1; git remote set-head origin -a >/dev/null 2>&1
YRC=$(bash -c "$SETUP" >/dev/null 2>&1; echo $?)
check "second repo with the same basename sets up cleanly" "$YRC" "0"
[ "$(key "$LAB/x/proj")" != "$(key "$LAB/y/proj")" ] \
  && ok "the two repos get different worktree keys" || bad "worktree keys collided"

echo "== 9. second task refuses a dirty tree, then switches in place =="
cd "$LAB/shared" || exit 1
WTS="$HOME/.claude-worktrees/$(key "$LAB/shared")/$SID"
echo dirty > "$WTS/leftover.txt"
DRC=$(cd "$WTS" && bash -c "$SECOND" >/dev/null 2>&1; echo $?)
[ "$DRC" -ne 0 ] && ok "refuses to start a new task on a dirty tree" || bad "carried WIP onto the new branch"
rm -f "$WTS/leftover.txt"
BEFORE=$(git worktree list | wc -l)
(cd "$WTS" && bash -c "$SECOND") >/dev/null 2>&1
check "switched to the new task branch" "$(git -C "$WTS" rev-parse --abbrev-ref HEAD)" \
  "jbarbier/next-task-$SID"
check "no new worktree" "$(git worktree list | wc -l)" "$BEFORE"

echo "== 10. sweep removes merged worktrees and keeps unmerged ones =="
cd "$LAB/shared" || exit 1
git switch -q main 2>/dev/null || git switch -q -c main origin/main
MERGED="$HOME/.claude-worktrees/$(key "$LAB/shared")/cccccccc"
git worktree add -q -b jbarbier/merged-cccccccc "$MERGED" origin/main
UNMERGED="$HOME/.claude-worktrees/$(key "$LAB/shared")/dddddddd"
git worktree add -q -b jbarbier/unmerged-dddddddd "$UNMERGED" origin/main
git -C "$UNMERGED" commit -q --allow-empty -m "real work not yet merged"
git switch -q someone-elses-wip
bash -c "$SWEEP" >/dev/null 2>&1
[ -d "$MERGED" ] && bad "sweep left a fully merged worktree behind" || ok "sweep removed the merged worktree"
[ -d "$UNMERGED" ] && ok "sweep kept the worktree with unmerged commits" || bad "sweep destroyed unmerged work"

echo "== 11. the branch prefix prefers the GitHub login over the email =="
printf '#!/bin/sh\necho jbarbier-gh\n' > "$LAB/bin/gh"; chmod +x "$LAB/bin/gh"
freshglobal "$LAB/gh.gitconfig" write0@gmail.com    # email local-part differs from gh login
mkrepo "$LAB/ghrepo" main
cd "$LAB/ghrepo" || exit 1; git remote set-head origin -a >/dev/null 2>&1
bash -c "$SETUP" >/dev/null 2>&1
check "used the gh login, not the email local-part" \
  "$(git -C "$HOME/.claude-worktrees/$(key "$LAB/ghrepo")/$SID" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
  "jbarbier-gh/fix-login-$SID"
nogh; export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
