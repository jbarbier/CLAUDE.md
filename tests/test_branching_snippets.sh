#!/usr/bin/env bash
# Runs the shell blocks EXACTLY as they appear in the "Branching" section of
# CLAUDE.md, extracted from the markdown rather than retyped, so the thing under
# test is literally the thing a reader copies.
#
# Every case is a defect that was found in review and reproduced, not a
# hypothetical. Each one fails if you revert the corresponding fix.
set -uo pipefail
DOC=${1:-"$(cd "$(dirname "$0")/.." && pwd)/CLAUDE.md"}
[ -f "$DOC" ] || { echo "no CLAUDE.md at $DOC"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

LAB=$(mktemp -d); trap 'rm -rf "$LAB"' EXIT
export HOME="$LAB/home"; mkdir -p "$HOME"
export PATH="$LAB/bin:$PATH"; mkdir -p "$LAB/bin"
nogh(){ printf '#!/bin/sh\nexit 1\n' > "$LAB/bin/gh"; chmod +x "$LAB/bin/gh"; }
nogh
freshglobal(){ export GIT_CONFIG_GLOBAL="$1"; : > "$1"
  git config --global user.name "Julien Barbier"
  git config --global user.email "${2:-jbarbier@example.com}"
  git config --global init.defaultBranch main; }
freshglobal "$HOME/.gitconfig"

extract(){ awk -v want="$1" '
    /^## Branching/ {inSec=1}
    inSec && /^## The two machine spaces/ {exit}
    inSec && /^ *```bash/ {n++; if(n==want){grab=1; next}}
    grab && /^ *```/ {exit}
    grab {sub(/^  /,""); print}' "$DOC"; }
SETUP=$(extract 1); BOOTSTRAP=$(extract 2); SECOND=$(extract 3)
GUARD=$(extract 4); SWEEP=$(extract 5)

mkrepo(){ git init -q --bare "$1.git"; git init -q -b "${2:-main}" "$1"
  git -C "$1" commit -q --allow-empty -m init
  git -C "$1" remote add origin "$1.git"; git -C "$1" push -q -u origin "${2:-main}"
  git -C "$1" remote set-head origin -a >/dev/null 2>&1; }
key(){ printf '%s-%s' "$(basename "$1")" "$(printf %s "$1" | cksum | cut -d' ' -f1)"; }
SID=1f3b76a3
run_setup(){ # $1 = session id, $2 = slug. Runs the shipped block verbatim.
  CLAUDE_CODE_SESSION_ID="$1" bash -c "$(echo "$SETUP" | sed "s/^SLUG=fix-login/SLUG=$2/")" 2>&1; }

echo "== 0. blocks extract, are self-contained, and have no placeholders =="
i=0
for blk in "$SETUP" "$BOOTSTRAP" "$SECOND" "$GUARD" "$SWEEP"; do
  i=$((i+1)); [ -n "$blk" ] || { bad "block $i empty (extraction broke)"; continue; }
  leak=""
  for v in WT OWNER BASE SID ROOT KEY SLUG HERE; do
    echo "$blk" | grep -q "\$$v" && ! echo "$blk" | grep -qE "^ *$v=" && leak="$leak \$$v"
  done
  [ -z "$leak" ] && ok "block $i is self-contained" || bad "block $i reads undefined:$leak"
done
echo "$SETUP" | grep -q '<.*>' && bad "setup has an unexplained placeholder" \
                               || ok "no unexplained placeholder in setup"

echo "== 1. THE core claim, using the shipped block: two sessions, two trees =="
mkrepo "$LAB/shared"
cd "$LAB/shared" || exit 1
git switch -q -c someone-elses-wip; git commit -q --allow-empty -m wip
OA=$(run_setup aaaa1111-x fix-login); RA=$?
OB=$(run_setup bbbb2222-x add-export); RB=$?
check "session A setup exits clean" "$RA" "0"
check "session B setup exits clean" "$RB" "0"
[ "$RA" = 0 ] || echo "$OA"
WA="$HOME/.claude-worktrees/$(key "$LAB/shared")/aaaa1111"
WB="$HOME/.claude-worktrees/$(key "$LAB/shared")/bbbb2222"
check "A branch" "$(git -C "$WA" rev-parse --abbrev-ref HEAD 2>/dev/null)" "jbarbier/fix-login-aaaa1111"
check "B branch" "$(git -C "$WB" rev-parse --abbrev-ref HEAD 2>/dev/null)" "jbarbier/add-export-bbbb2222"
echo "A work" > "$WA/f.txt"; echo "B work" > "$WB/f.txt"
git -C "$WB" switch -q -c jbarbier/third-bbbb2222        # B starts another task
check "A's file survived B's branch switch" "$(cat "$WA/f.txt")" "A work"
check "A's branch survived B's branch switch" \
  "$(git -C "$WA" rev-parse --abbrev-ref HEAD)" "jbarbier/fix-login-aaaa1111"
check "shared checkout never moved" "$(git branch --show-current)" "someone-elses-wip"
check "based on the remote default, not the wip branch" \
  "$(git -C "$WA" rev-parse HEAD)" "$(git rev-parse origin/main)"
echo "$OA" | grep -q "^WORKTREE " && ok "prints the path for EnterWorktree" || bad "no WORKTREE line"

echo "== 2. an unset session id must STOP, not silently share one tree =="
mkrepo "$LAB/nosid"; cd "$LAB/nosid" || exit 1
OUT=$(env -u CLAUDE_CODE_SESSION_ID bash -c "$SETUP" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok "setup refuses when CLAUDE_CODE_SESSION_ID is unset" \
                || bad "setup continued with an empty session id"
echo "$OUT" | grep -q "CLAUDE_CODE_SESSION_ID" && ok "says why" || bad "no explanation: $OUT"
check "no worktree was created" "$(git worktree list | wc -l)" "1"

echo "== 3. a failed worktree add must not report success =="
mkrepo "$LAB/dup"; cd "$LAB/dup" || exit 1
git branch jbarbier/fix-login-eeee5555 origin/main          # branch already taken
OUT=$(run_setup eeee5555-x fix-login); RC=$?
[ "$RC" -ne 0 ] && ok "setup fails when the branch already exists" \
                || bad "setup returned 0 after a fatal worktree add"
echo "$OUT" | grep -q "^WORKTREE " && bad "printed a WORKTREE path that was never created" \
                                   || ok "did not print a path it failed to create"

echo "== 4. resume re-attaches without duplicating =="
cd "$LAB/shared" || exit 1
N=$(git worktree list | wc -l); B=$(git branch --list | wc -l)
OUT=$(run_setup aaaa1111-x fix-login); check "resume exits clean" "$?" "0"
echo "$OUT" | grep -q "re-attaching" && ok "reports re-attaching" || bad "got: $OUT"
check "no duplicate worktree" "$(git worktree list | wc -l)" "$N"
check "no stray branch" "$(git branch --list | wc -l)" "$B"

echo "== 5. guard: shared checkout vs any linked worktree =="
cd "$LAB/shared" || exit 1
bash -c "$GUARD" 2>&1 | grep -q "WRONG TREE" && ok "fires in the shared checkout" \
                                             || bad "silent in the shared checkout"
G=$(cd "$WA" && bash -c "$GUARD" 2>&1)
check "silent in this session's worktree" "$G" ""
# a harness-provided worktree, named the way the tool names them, must also pass
git worktree add -q -b harness-style "$HOME/.claude-worktrees/plain/1f3b76a3" origin/main
GH_=$(cd "$HOME/.claude-worktrees/plain/1f3b76a3" && bash -c "$GUARD" 2>&1)
check "silent in a harness-provided worktree (no re-derivation fight)" "$GH_" ""
mkdir -p "$LAB/linkhome"; ln -s "$LAB/home" "$LAB/linkhome/h"
GS=$(cd "$LAB/linkhome/h/.claude-worktrees/$(key "$LAB/shared")/aaaa1111" 2>/dev/null && bash -c "$GUARD" 2>&1)
check "silent when reached through a symlinked path" "$GS" ""
# Run from a SUBDIRECTORY, both sides. git rev-parse returns --git-common-dir
# relative to the cwd unless --path-format=absolute is asked for, so a guard that
# drops that flag goes SILENT in the shared checkout, which is the failure that
# actually loses work. Pin both directions.
mkdir -p "$LAB/shared/src/deep" "$WA/src/deep"
GSUB=$(cd "$LAB/shared/src/deep" && bash -c "$GUARD" 2>&1)
echo "$GSUB" | grep -q "WRONG TREE" && ok "fires from a subdirectory of the shared checkout" \
                                    || bad "SILENT from a subdirectory of the shared checkout: '$GSUB'"
GWSUB=$(cd "$WA/src/deep" && bash -c "$GUARD" 2>&1)
check "silent from a subdirectory of a worktree" "$GWSUB" ""

echo "== 5b. solo mode: no worktree, no PR, and the guard goes quiet =="
mkrepo "$LAB/solo"
cd "$LAB/solo" || exit 1
git config claude.mode solo
SOUT=$(CLAUDE_CODE_SESSION_ID=cccc3333 bash -c "$(echo "$SETUP" | sed 's/^SLUG=fix-login/SLUG=solo-task/')" 2>&1)
echo "$SOUT" | grep -q "^SOLO solo-task$" && ok "setup reports SOLO and the branch" \
                                          || bad "got: $SOUT"
check "made no worktree" "$(git worktree list | wc -l)" "1"
check "switched to the task branch" "$(git branch --show-current)" "solo-task"
# solo must not need a session id: that is the whole point for non-Claude agents
git switch -q "$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|origin/||')"
git branch -qD solo-task
SOUT2=$(env -u CLAUDE_CODE_SESSION_ID bash -c "$(echo "$SETUP" | sed 's/^SLUG=fix-login/SLUG=no-sid/')" 2>&1)
echo "$SOUT2" | grep -q "^SOLO no-sid$" && ok "works with no session id set" \
                                        || bad "got: $SOUT2"
# the dirty-tree trap the team path has: switch -c would carry the work over
echo dirt > dirty.txt
SOUT3=$(bash -c "$(echo "$SETUP" | sed 's/^SLUG=fix-login/SLUG=dirty-task/')" 2>&1)
echo "$SOUT3" | grep -q "STOP: commit or stash first" && ok "refuses a dirty tree" \
                                                      || bad "got: $SOUT3"
rm -f dirty.txt
# and the guard must be silent here: the shared checkout IS the workplace in solo
GSOLO=$(bash -c "$GUARD" 2>&1)
check "guard silent in solo mode" "$GSOLO" ""
# flipping back to team must restore the alarm, or the switch is a one-way door
git config claude.mode team
GTEAM=$(bash -c "$GUARD" 2>&1)
echo "$GTEAM" | grep -q "WRONG TREE" && ok "guard fires again after mode=team" \
                                     || bad "guard stayed quiet in team mode: '$GTEAM'"
# unset must behave as team, since that is the documented default
git config --unset claude.mode
GUNSET=$(bash -c "$GUARD" 2>&1)
echo "$GUNSET" | grep -q "WRONG TREE" && ok "unset mode defaults to team" \
                                      || bad "unset mode behaved as solo: '$GUNSET'"
SOUT4=$(CLAUDE_CODE_SESSION_ID=dddd4444 bash -c "$(echo "$SETUP" | sed 's/^SLUG=fix-login/SLUG=team-task/')" 2>&1)
echo "$SOUT4" | grep -q "^WORKTREE " && ok "unset mode still builds a worktree" \
                                     || bad "got: $SOUT4"

echo "== 6. repo paths with spaces, master default, and no remote at all =="
mkdir -p "$LAB/my app"; mkrepo "$LAB/my app/proj"; cd "$LAB/my app/proj" || exit 1
run_setup 11111111-x fix-login >/dev/null 2>&1
[ -d "$HOME/.claude-worktrees/$(key "$LAB/my app/proj")/11111111" ] \
  && ok "path with a space survives" || bad "path truncated at the space"
mkrepo "$LAB/oldrepo" master; cd "$LAB/oldrepo" || exit 1
git remote set-head origin -d >/dev/null 2>&1
run_setup 22222222-x fix-login >/dev/null 2>&1
check "master repo with origin/HEAD unset" \
  "$(git -C "$HOME/.claude-worktrees/$(key "$LAB/oldrepo")/22222222" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
  "jbarbier/fix-login-22222222"
git init -q -b main "$LAB/noremote"; cd "$LAB/noremote" || exit 1
git commit -q --allow-empty -m init                    # no origin at all: exercises the ladder
OUT=$(run_setup 33333333-x fix-login); check "repo with no remote exits clean" "$?" "0"
[ "$?" = 0 ] || echo "    $OUT"
check "no-remote worktree on its branch" \
  "$(git -C "$HOME/.claude-worktrees/$(key "$LAB/noremote")/33333333" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
  "jbarbier/fix-login-33333333"

echo "== 7. owner: cached per repo, never cached empty, gh beats email =="
freshglobal "$LAB/g2" ""
mkrepo "$LAB/noowner"; cd "$LAB/noowner" || exit 1
git config user.email ""
OUT=$(run_setup 44444444-x fix-login); RC=$?
[ "$RC" -ne 0 ] && ok "refuses when no owner resolves" || bad "built a branch with an empty owner"
check "nothing cached globally" "$(git config --global claude.branchPrefix)" ""
printf '#!/bin/sh\necho jbarbier-gh\n' > "$LAB/bin/gh"; chmod +x "$LAB/bin/gh"
freshglobal "$LAB/g3" write0@gmail.com
mkrepo "$LAB/ghrepo"; cd "$LAB/ghrepo" || exit 1
run_setup 55555555-x fix-login >/dev/null 2>&1
check "gh login beats the email local-part" \
  "$(git -C "$HOME/.claude-worktrees/$(key "$LAB/ghrepo")/55555555" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
  "jbarbier-gh/fix-login-55555555"
check "prefix cached in the repo, not globally" "$(git config --local claude.branchPrefix)" "jbarbier-gh"
check "global config left alone" "$(git config --global claude.branchPrefix)" ""
nogh; freshglobal "$HOME/.gitconfig"

echo "== 8. second task: refuses dirty, and survives an unset origin/HEAD =="
cd "$LAB/shared" || exit 1
echo dirty > "$WA/leftover.txt"
RC=$(cd "$WA" && bash -c "$SECOND" >/dev/null 2>&1; echo $?)
[ "$RC" -ne 0 ] && ok "refuses to start task two on a dirty tree" || bad "carried WIP to the new branch"
rm -f "$WA/leftover.txt"
git -C "$WA" add -A; git -C "$WA" commit -qm "task one work"   # tree must be clean to move on
git remote set-head origin -d >/dev/null 2>&1          # the state the setup ladder exists for
N=$(git worktree list | wc -l)
(cd "$WA" && CLAUDE_CODE_SESSION_ID=aaaa1111-x bash -c "$SECOND") >/dev/null 2>&1
check "task two switched branch even with origin/HEAD unset" \
  "$(git -C "$WA" rev-parse --abbrev-ref HEAD)" "jbarbier/next-task-aaaa1111"
check "task two created no new worktree" "$(git worktree list | wc -l)" "$N"
git remote set-head origin -a >/dev/null 2>&1

echo "== 9. the sweep must not eat live work =="
cd "$LAB/shared" || exit 1
git switch -q main 2>/dev/null || git switch -q -c main origin/main
printf '.env\n' > "$LAB/shared/.gitignore"; git add -A; git commit -qm ign
git push -q origin main; git remote set-head origin -a >/dev/null 2>&1

# (i) a live session that has done no work and never pushed
FRESH="$HOME/.claude-worktrees/$(key "$LAB/shared")/66666666"
git worktree add -q -b jbarbier/fresh-66666666 "$FRESH" origin/main

# (ii) pushed and merged, but still holding a gitignored .env
ENVWT="$HOME/.claude-worktrees/$(key "$LAB/shared")/77777777"
git worktree add -q -b jbarbier/env-77777777 "$ENVWT" origin/main
git -C "$ENVWT" commit -q --allow-empty -m "env work"
git -C "$ENVWT" push -q -u origin HEAD
git -C "$ENVWT" push -q origin HEAD:main                     # its PR landed
printf 'SECRET=hunter2\n' > "$ENVWT/.env"

# (iii) pushed, merged, nothing left behind: the only one that should go
DONE="$HOME/.claude-worktrees/$(key "$LAB/shared")/88888888"
git worktree add -q -b jbarbier/done-88888888 "$DONE" origin/main
git -C "$DONE" commit -q --allow-empty -m "real work"
git -C "$DONE" push -q -u origin HEAD
git -C "$DONE" push -q origin HEAD:main                      # its PR landed
git fetch -q origin; git remote set-head origin -a >/dev/null 2>&1
bash -c "$SWEEP" >/dev/null 2>&1
[ -d "$FRESH" ] && ok "kept a fresh worktree that had done no work" \
                || bad "DELETED a fresh worktree: this is the bug that ate live sessions"
[ -f "$ENVWT/.env" ] && ok "kept a worktree holding an ignored .env" \
                     || bad "DELETED an ignored .env that git would not have protected"
[ -d "$DONE" ] && bad "kept a genuinely merged, clean worktree" \
               || ok "removed the genuinely merged, clean worktree"
git show-ref --verify --quiet refs/heads/jbarbier/done-88888888 \
  && ok "sweep kept the branch" || bad "sweep deleted the branch"

echo "== 10. the sweep never deletes the tree you are standing in =="
SELF="$HOME/.claude-worktrees/$(key "$LAB/shared")/99999999"
git worktree add -q -b jbarbier/self-99999999 "$SELF" origin/main
(cd "$SELF" && bash -c "$SWEEP") >/dev/null 2>&1
[ -d "$SELF" ] && ok "refused to delete its own working directory" \
               || bad "deleted the cwd it was running in"

echo "== 11. the sweep sees through a rebase merge (SHA changes, patch does not) =="
# GitHub's "Rebase and merge" and "Squash and merge" both replay the work as a
# NEW commit. The branch tip is then not an ancestor of the base, so an
# ancestry-only test keeps every merged worktree forever. Reproduced here by
# cherry-picking, which is what a rebase merge does server-side.
cd "$LAB/shared" || exit 1
git switch -q main; git fetch -q origin; git merge -q --ff-only origin/main   # case 9 pushed past us
RB="$HOME/.claude-worktrees/$(key "$LAB/shared")/aaaaaaaa"
git worktree add -q -b jbarbier/rebased-aaaaaaaa "$RB" origin/main
printf 'landed via rebase\n' > "$RB/rebased.txt"
git -C "$RB" add rebased.txt; git -C "$RB" commit -qm "work that gets rebase-merged"
git -C "$RB" push -q -u origin HEAD
RBSHA=$(git -C "$RB" rev-parse HEAD)
git switch -q main
# GitHub replays the commit under its own committer identity and timestamp, so the
# SHA changes. Pin the committer date, or a same-second replay onto the same parent
# hashes to the identical object and the test proves nothing.
GIT_COMMITTER_DATE="2030-01-01T00:00:00 +0000" git cherry-pick "$RBSHA" >/dev/null
git push -q origin main
# and a branch with real work that has NOT landed: relaxing the test must not eat it
LIVE="$HOME/.claude-worktrees/$(key "$LAB/shared")/bbbbbbbb"
git worktree add -q -b jbarbier/live-bbbbbbbb "$LIVE" origin/main
printf 'still in review\n' > "$LIVE/live.txt"
git -C "$LIVE" add live.txt; git -C "$LIVE" commit -qm "work still open"
git -C "$LIVE" push -q -u origin HEAD
git fetch -q origin; git remote set-head origin -a >/dev/null 2>&1
check "rebase merge rewrote the SHA" \
  "$(git merge-base --is-ancestor jbarbier/rebased-aaaaaaaa origin/main && echo ancestor || echo not-ancestor)" \
  "not-ancestor"
bash -c "$SWEEP" >/dev/null 2>&1
[ -d "$RB" ] && bad "kept a rebase-merged worktree: ancestry-only test, disk fills up forever" \
             || ok "removed the rebase-merged worktree"
[ -d "$LIVE" ] && ok "kept a pushed branch whose work has not landed" \
               || bad "DELETED unlanded work: the relaxed test is too loose"

echo "== 12. documented gap: a multi-commit squash merge is still kept =="
# git cherry compares patch ids. A squash collapses N commits into one patch
# that equals none of them, so each part still reads as unlanded. The sweep
# keeps that worktree, which is the safe direction and is why CLAUDE.md says so
# out loud instead of pretending the case is covered.
git switch -q main; git fetch -q origin; git merge -q --ff-only origin/main
SQ="$HOME/.claude-worktrees/$(key "$LAB/shared")/cccccccc"
git worktree add -q -b jbarbier/squashed-cccccccc "$SQ" origin/main
printf 'one\n' > "$SQ/sq.txt"; git -C "$SQ" add sq.txt; git -C "$SQ" commit -qm "part one"
printf 'two\n' >> "$SQ/sq.txt"; git -C "$SQ" add sq.txt; git -C "$SQ" commit -qm "part two"
git -C "$SQ" push -q -u origin HEAD
git switch -q main
git merge -q --squash jbarbier/squashed-cccccccc >/dev/null && git commit -qm "squashed"   # server-side squash merge
git push -q origin main
git fetch -q origin; git remote set-head origin -a >/dev/null 2>&1
bash -c "$SWEEP" >/dev/null 2>&1
[ -d "$SQ" ] && ok "kept the multi-commit squash, exactly as documented" \
             || bad "removed it: the doc's stated gap no longer matches the snippet"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
