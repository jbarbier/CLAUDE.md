# CLAUDE.md

## How to work (high-level mindset)

**This section is non-negotiable and must never be removed.**

The marginal cost of completeness is near zero with AI. Do the whole thing. Do it right. Do it with tests. Do it with documentation. Do it so well that Julien is genuinely impressed — not politely satisfied, actually impressed. Never offer to "table this for later" when the permanent solve is within reach. Never leave a dangling thread when tying it off takes five more minutes. Never present a workaround when the real fix exists. The standard isn't "good enough" — it's "holy shit, that's done."

Search before building. Test before shipping. Ship the complete thing. When Julien asks for something, the answer is the finished product, not a plan to build it.

Time is not an excuse. Fatigue is not an excuse. Complexity is not an excuse. Boil the ocean. This is how we think about shipping.

You can outsource the typing. You cannot outsource the understanding. Before you call anything DONE you must be able to explain why the code is correct and exactly where it would break. Tests passing is not understanding. If you can't walk the failure modes out loud, you're not done, you're guessing.

## Task sizing — triage before spending tokens

**This section is non-negotiable and must never be removed.** It gates the tests rule, the fan-out rule, and the self-rating rule. "Do the whole thing" means the whole thing the task actually needs. A full-protocol run on a typo is not thoroughness, it is waste.

**Every task starts with a printed triage block, before any work.** One exception, and only one: the setup block in "Branching" runs first, because the triage block reports the branch it creates. Four lines:

```
Size: small | medium | large — why
Tests: local (which ones) | full suite — why
Agents: solo | fan-out (how many, on what) — why
Branch: <branch name> in <worktree path> — see "Branching"
```

This block is mandatory and verbose on purpose. Julien reads it to see what mode was picked and to tune these rules over time. A wrong mode is only correctable if the choice is visible. Never skip it, never bury it mid-report. The Branch line is there so that with several sessions running at once, Julien can tell at a glance which one is about to touch what.

**The sizes:**

- **small** — typo, copy change, color or styling value, config tweak, rename, any one-or-two-file mechanical edit with no behavior change. Solo, no fan-out, no variant tournament, no critic sub-agent. Run only the checks that cover what was touched: the module's existing tests, lint, build. A non-behavioral change needs no new test. Self-rating is one line, no loop. Commit and push as usual.
- **medium** — localized behavior change or bug fix inside one service or module. Solo by default; fan out only if the work splits into truly independent units. Run the touched service's test suite, not the whole repo's. Bug fixes still ship the regression test. One cold critic pass, no tournament.
- **large** — new feature, cross-service or contract change, architecture work, anything judgment-heavy (design, approach, UX). Full protocol: fan-out, variant tournament, harsh critic loop, full test + eval suites for every service touched, self-rating loop.

**Deciding rules:**

- When torn between two sizes, pick the smaller one and say so in the triage block. Escalating mid-task is cheap; burning a large-protocol run on a small change is not.
- Escalate the moment the change turns out bigger than triaged (touches a contract, spreads across services, needs judgment). Print an updated triage block right then, with what changed the call.
- "Test what you touch" is the default. The full suite is for large changes and contract changes. The blast radius decides, not habit: if the diff cannot reach code outside the touched module, running that module's tests IS the complete verification.
- The final report restates what was actually run (which tests, which agents) so the triage call can be judged after the fact.

## Branching — one session, one worktree, one branch

**This section is non-negotiable and must never be removed.** It runs first, before the triage block, because the triage block has to report the branch it produces.

Two facts hold at once: Julien works with other people, so nothing lands on `main` directly; and several Claude Code sessions run on the same machine, in the same repo, at the same time.

**Creating a branch does not isolate a session.** Every session started in the same directory shares one working tree. The moment session B runs `git switch -c`, session A's files change on disk underneath it, mid-edit. Session A then commits B's tree, or fails a test for reasons that live in another conversation. The branch name is not what collides, the working tree is, so the fix belongs at the working tree.

**The rule: the worktree is the session. The branch is the task.** Each session gets its own git worktree, keyed by its session id, and makes as many task branches inside it as it likes. Git helps a little (it refuses to check out one branch in two worktrees) but it will not stop you editing the shared checkout. That part is on the guard below, so run it.

Throughout: the **shared checkout** is the original clone, the one everybody's `cd` lands in and the one `git worktree list` prints first. Nobody edits there.

**Setup — once per session, before the first write.** Run it from the shared checkout. `SLUG` is the only blank to fill: lowercase, dash separated, three words at most (`fix-login`, `stripe-webhook-retry`).

```bash
SLUG=fix-login                                                    # <- the task, kebab-case
SID=${CLAUDE_CODE_SESSION_ID:0:8}
[ -n "$SID" ] || { echo "STOP: CLAUDE_CODE_SESSION_ID is unset, every session would share one worktree"; exit 1; }
ROOT=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
KEY=$(basename "$ROOT")-$(printf %s "$ROOT" | cksum | cut -d' ' -f1)   # unique per repo PATH
WT="$HOME/.claude-worktrees/$KEY/$SID"

OWNER=$(git config claude.branchPrefix)
[ -n "$OWNER" ] || OWNER=$(gh api user --jq .login 2>/dev/null)
[ -n "$OWNER" ] || OWNER=$(git config user.email | cut -d@ -f1)
[ -n "$OWNER" ] || { echo "STOP: git config claude.branchPrefix YOUR_HANDLE"; exit 1; }
git config claude.branchPrefix "$OWNER"          # repo-local: work and personal handles differ

git fetch -q origin 2>/dev/null
git remote set-head -a origin >/dev/null 2>&1                     # repair origin/HEAD if unset
BASE=$(git symbolic-ref -q --short refs/remotes/origin/HEAD)
for c in origin/main origin/master main master; do
  [ -n "$BASE" ] && break
  git rev-parse -q --verify "$c" >/dev/null && BASE=$c
done
[ -n "$BASE" ] || { echo "STOP: cannot find a base branch"; exit 1; }

if git worktree list --porcelain | grep -qFx "worktree $WT"; then   # resumed session
  echo "re-attaching to existing worktree"
else
  git worktree add -b "$OWNER/$SLUG-$SID" "$WT" "$BASE" || exit 1   # never report a tree we failed to make
fi
echo "WORKTREE $WT"
```

Run that block as a unit; each Claude Code Bash call is already its own shell, so the `exit 1` lines are failure stops, not something that ends your session. Pasting it into your own terminal by hand is the one case where that matters: use `bash -c` there.

Then move the session into it: call `EnterWorktree` with `path` set to the `WORKTREE` path the block just printed (this section is the project instruction that authorizes that tool). Outside Claude Code, `cd` to it. The block prints the path on purpose, because `$WT` is gone by the next tool call.

**Then bootstrap the worktree, before the first test run.** A worktree contains tracked files only. `.env`, `node_modules/`, virtualenvs and build caches are gitignored, so they are absent, and the first command you run fails for a reason that has nothing to do with your change. Bring over what the project needs and run its install step once, when the worktree is created. Symlink the big directories, copy the small secrets:

```bash
ROOT=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
[ -f "$ROOT/.env" ] && cp "$ROOT/.env" .        # the copy is per-worktree; the VALUES inside are not
[ -d "$ROOT/node_modules" ] && ln -s "$ROOT/node_modules" node_modules   # big, shared, not copied
git submodule update --init --recursive 2>/dev/null   # worktrees do not inherit submodules
# then the project's own install/build step, e.g. npm ci / uv sync / bundle install
```

Adjust the list to the project. Never commit those files to fix this.

- **A worktree isolates files in the repo, and nothing else.** The copied `.env` points both sessions at one database, one dev port, one redis, one bucket prefix, one compose project. Two sessions then run migrations against the same schema, and each one sees the other's failures as a bug in its own change. Before the first run, fork every shared handle per session: suffix the database name with `${CLAUDE_CODE_SESSION_ID:0:8}`, offset the port, prefix the compose project, and drop the fork at the end of the task the same way you drop the worktree. This is not a snippet on purpose. The names belong to the project, not to git, and a generic rewrite of `DATABASE_URL` would be wrong more often than right.
- **The branch prefix comes from the GitHub login, not the email.** They are often different: a `user.email` local-part can be an old handle teammates have never seen. It is cached per repo, not globally, because a work account and a personal account resolve to different handles on the same machine. Override with `git config claude.branchPrefix`. Never cache an empty value: `git config` returns success on an empty string, so one bad write would poison the repo until someone unset it by hand.
- **Base off the remote default branch, never local HEAD.** A session that branches off whatever the shared checkout is sitting on inherits another session's half-finished work. Do not hardcode `origin/main`: plenty of repos are `master`, and `origin/HEAD` is unset on any repo built with `git init` plus `git remote add`.
- **Shell variables do not survive between tool calls.** `SID`, `WT`, `OWNER` and `BASE` are gone by the next command, so every snippet here re-derives what it needs. Re-derive, don't remember.
- **Second task, same session: new branch, same worktree, clean tree first.** `git switch -c` carries uncommitted work onto the new branch, which quietly contaminates the next task with the last one. Resolve the base the same way setup does, because an unset `origin/HEAD` would otherwise put task two on task one's branch and into task one's PR:

  ```bash
  SLUG=next-task                                                  # <- the new task
  git status --porcelain | grep -q . && { echo "STOP: commit or stash first"; exit 1; }
  git fetch -q origin 2>/dev/null
  git remote set-head -a origin >/dev/null 2>&1
  BASE=$(git symbolic-ref -q --short refs/remotes/origin/HEAD)
  for c in origin/main origin/master main master; do
    [ -n "$BASE" ] && break
    git rev-parse -q --verify "$c" >/dev/null && BASE=$c
  done
  [ -n "$BASE" ] || { echo "STOP: cannot find a base branch"; exit 1; }
  git switch -c "$(git config claude.branchPrefix)/$SLUG-${CLAUDE_CODE_SESSION_ID:0:8}" "$BASE" || exit 1
  ```

  Never a second worktree.
- **Resuming re-attaches, it does not duplicate.** The path is derived from the session id, so re-running the setup block finds the existing worktree and enters it. Note what it does *not* do: it does not create the new branch. If you are resuming into a different task, run the second-task block after it.

**The guard — run it before the first write of every task, and after any compaction.** One question only: am I about to write in the shared checkout?

```bash
ROOT=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
[ "$(git rev-parse --show-toplevel)" = "$(cd "$ROOT" && pwd -P)" ] \
  && echo "WRONG TREE — you are in the shared checkout, set up a worktree"
```

Both sides resolve symlinks, because `git rev-parse --show-toplevel` does and a raw `$HOME` does not; comparing them unresolved reports WRONG TREE forever on any machine whose home is a symlink, and a guard that cries wolf teaches you to ignore the one check that matters. The guard deliberately accepts *any* linked worktree rather than only the one this block would build, so that a sub-agent placed in a harness-provided worktree passes instead of being sent back into the parent's tree.

If it trips, stop. Do not edit, do not commit, do not "just switch the branch quickly". Set the worktree up and start again. If you already changed files in the shared checkout before noticing, do not throw them away and do not commit them there: `git stash -u` in the shared checkout, run the setup, then `git stash pop` inside the new worktree.

**Sub-agents share the parent's worktree, so parallel builders must not.** Sub-agents inherit the parent's `CLAUDE_CODE_SESSION_ID` verbatim and resolve to the parent's worktree. For a sub-agent that only reads, or for units that run one after another, that is correct and cheap. But two builders editing the same files in one working tree is the collision this whole section exists to prevent, just moved inside a single session. So: **any sub-agents that write in parallel — every variant tournament in "Fan-out + harsh critic", and any fan-out whose units touch overlapping files — must be launched with `isolation: "worktree"`**, which makes the harness give each one its own tree.

**Shipping the branch (the full ritual is in "After every task"):** rebase on the base branch, push, open a PR, let a human merge it. Never push to `main`, and never merge your own PR unless Julien says so.

**After the first push, rebase means `--force-with-lease --force-if-includes`.** Rebasing rewrites commits you already pushed, so the next plain push is rejected as non-fast-forward. `--force-with-lease` alone is not the safety net it looks like here: the documented ritual fetches first, and that fetch updates the remote-tracking ref the lease is compared against, so a teammate's commit pushed to your branch is silently destroyed (verified). `--force-if-includes` is the part that actually refuses, because it checks that the commit you are overwriting is one your local branch has integrated. Use both, on your own session branch only. That pair is the one carve-out from the force-push ban in "Safety"; it does not extend to shared branches, and never to `main`.

**Cleanup is a manual command, never part of setup.** Worktrees are not free (each is a full checkout), but a sweep that runs automatically will eventually run while somebody else is mid-task, so it runs when Julien asks, from the shared checkout:

```bash
HERE=$(git rev-parse --show-toplevel)
BASE=$(git symbolic-ref -q --short refs/remotes/origin/HEAD) || exit 1
git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' |
  grep "/\.claude-worktrees/" | while read -r w; do
    [ "$w" = "$HERE" ] && continue                       # never the tree you are standing in
    b=$(git -C "$w" branch --show-current); [ -n "$b" ] || continue
    up=$(git -C "$w" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
    [ "$up" = "origin/$b" ] || continue                  # never pushed under its own name
    git merge-base --is-ancestor "$b" "$BASE" || continue                # not merged yet
    [ -n "$(git -C "$w" status --porcelain --ignored)" ] && continue     # something left behind
    git worktree remove "$w"
  done
git worktree prune
```

The four `continue` lines are the whole point, and each one is a bug that bit:

- **Never the cwd**, or running the sweep from inside your own worktree deletes the directory you are standing in.
- **Never a branch that was not pushed under its own name.** "Is it merged" is not a safe test on its own: a brand-new branch is an ancestor of the base, so a naive sweep deletes every session that has not committed yet, including other people's live work. Note the check is `upstream = origin/<branch>`, not merely "has an upstream": `git worktree add -b X ... origin/main` sets X's upstream to `origin/main` straight away, so the weaker test passes for a worktree that has done nothing at all.
- **Merged into the base**, the obvious one.
- **`--ignored` clean.** `git worktree remove` refuses on modified and untracked files but deletes **ignored** ones without complaint (verified: `rc=0`, directory gone), and ignored is exactly where the bootstrap step puts `.env`. Git will not protect that file, so we do.

Removing a worktree never deletes its branch.

Running `git worktree` admin commands against the shared checkout is fine and is not "working" in it. To return there from inside a worktree, use `ExitWorktree` with `keep`.

**Never:** edit or commit in the shared checkout, run `git switch` or `git checkout` there, commit a worktree directory, or share one branch between two sessions.

This applies at every triage size, but scale the ceremony: a typo fix gets a branch and a PR, not a full-protocol run. The branch is cheap; the protocol is what "Task sizing" rations.

## The two machine spaces — read this before doing anything

Every piece of work you do belongs to one of two spaces. Picking the wrong one is the single most common way agents produce bad output.

**Latent space = LLM work.** Judgment, pattern matching, creativity, open-ended analysis, prose generation, ambiguous inputs. Cost: model tokens. Variability: high. Inspectability: none. Use when the task genuinely requires reasoning.

**Deterministic space = code.** Precision, reproducibility, speed, zero cost per run, testable. Cost: one-time write. Variability: zero. Inspectability: total. Use when the task is same-input-same-output.

**The rule:** if the same question asked twice would produce the same correct answer by definition, it's deterministic work. Do NOT do it in latent space. Write the script. If you find yourself doing arithmetic, timezone conversion, date math, file lookups, CSV parsing, JSON transforms, regex matches, hash computations, or structured API calls inside a model reply, stop and write a script.

**The meta-loop that makes this work:** the LLM writes the deterministic script, then the script constrains the LLM forever after. The model's intelligence creates the constraint that prevents the model from being stupid. A bug in latent space becomes a feature in deterministic space, and the old failure path becomes structurally unreachable.

Every feature, every fix, every investigation starts with: is this latent or deterministic? If the answer is "both," split it. The deterministic piece becomes a script + tests. The latent piece becomes a prompt + eval.

## The context window is the lever

The context window is your only control surface over the model. Treat it as a deliberate input, not a dumping ground. Load the spec, the contract, the relevant files, and concrete examples. Leave the noise out. A vague or bloated context produces vague or bloated output, every time. When a task goes sideways, the first question is "what was in the window," not "was the model dumb." Curate before you prompt.

## Non-negotiable rules

### Tests and evals — every time, no exceptions

- Scope what you RUN by the triage size (see "Task sizing"): small and medium changes run only the tests covering the touched code; the full suite is for large and contract changes. State in the report which lane ran and why. Never run the whole repo's suite for a few-words diff, and never skip the local checks either.
- What you WRITE still follows the rules below. "No new test needed" applies only to non-behavioral small changes (typo, copy, styling value); every behavior change ships its test.
- Every feature ships with a test suite AND an eval suite, in the same commit. Not the next PR.
- Every bug fix ships with a test AND an eval that would have caught the bug. The regression test is the proof the bug is fixed. The eval is the proof the fix generalizes.
- Every failure gets skillified (the 10 steps). Same day. Same session when possible.
- "I'll add tests later" is banned. If the tests/evals aren't in the diff, the work isn't done.
- Two test lanes, different budgets:
  - **Gate tests** — deterministic, local, free, <2s. Run on every commit via pre-commit hook. Never flaky.
  - **Periodic evals** — paid (LLM calls), slower, quality-measuring. Run before ship and nightly. Allowed to be non-deterministic but must have a pass threshold.

### Verify every example you ship — three passes, minimum

- Anything a reader will copy and run — a command, a prompt, an exercise, a number, a link — gets checked by you before it ships. Not reasoned about. Run.
- Three passes minimum, and say what each pass was. Deterministic claims (arithmetic, dates, API existence, file contents) get a script. Links get fetched and the title read, not just a 200. Exercises get walked start to finish as the reader would.
- Examples rot. An example that was true against one model generation can be false against the next. Re-verify on every revision; never inherit a claim from an earlier draft because it was checked once.
- Anything you could not verify is stated as unverified, in a verification log, with what would settle it. Never launder an unchecked claim into confident prose.
- Design the exercise so it teaches under every plausible outcome. If the lesson only lands when the tool fails in one specific way, the exercise is broken the day the tool improves.

### Quality first, length second

- Given a choice between covering the scope in less time and covering it properly in more, take more. More units, more days, more files. Never compress by lowering the bar.
- "Shorter" is not a goal. "Complete, correct, and understood" is. If it needs twice the space to be right, it gets twice the space.

### Tie every change to a measurable outcome

- Every feature names the outcome it moves before you build it: the metric, the workflow step, or the user-visible behavior that changes. "It works" is not an outcome.
- If you can't state what gets measurably better and how you'll see it, that's a Confusion Protocol stop, not a license to build.
- Wire in the trace. The change leaves evidence you can point at later: a metric, a log line, an eval score. Compute that produces no measurable, traceable result is theater.

### LLM access — local Claude Code, not the API

- When the software we build needs to call an LLM, do NOT use an LLM API (Anthropic API, OpenAI API, any hosted inference endpoint) unless Julien explicitly instructs it. Route the call through the local Claude Code instead.
- If no LLM service exists yet in the project, build one. Create a self-contained LLM service (under `services/llm/` per the architecture rules) that shells out to local Claude Code, with its own contract, tests, and evals. Every other service calls that contract, never an external API.
- Always use the best available model by default unless Julien explicitly instructs otherwise. No silent downgrades to a cheaper or smaller model for cost.

### Tech choice — vanilla by default

- Simplest vanilla tech wins. No framework-of-the-month. No clever abstractions for hypothetical reuse.
- Do not recreate what already exists. Before writing a utility, harness, or library, check for an existing lib that solves it.
- For cross-cutting concerns (eval harness, prompt library, vision utilities, observability, SEO, schema validation, etc.) grep GitHub in parallel for top candidates. Rank by stars, recency of last commit, issue responsiveness, and real user feedback (HN, Reddit, production write-ups). Return the best option with reasoning, not a list. Example: "for SEO in this project, use X because [stars, last commit 2 weeks ago, 48 issues closed in last month]. Second choice Y. Rejected Z because [last commit 14 months ago]."
- If two options are equally viable, name the trade-off explicitly and ask Julien. Confusion Protocol applies.

### Search before building

Three layers, in order:

1. **Tried-and-true.** Is there a standard library or pattern that does this? Use it.
2. **New-and-popular.** Is there a newer library with real traction? Evaluate it.
3. **First-principles.** Does the conventional approach actually apply here? If our situation is genuinely different, document WHY before writing custom code.

Most of the time Layer 1 wins. Default to that. If Layer 3 produces a genuine insight contradicting conventional wisdom, log it as a note in the commit or a design doc.

### Check for skills

When a task matches a specialized domain (SEO, schema, security audit, design review, etc.), use the installed Claude Code skill. Don't reinvent what gstack or a community skill already does well. Invoke via the Skill tool, not by re-implementing.

### Skillify repeated success, not just failure

Failures get skillified — that rule already stands. So does repeated success. The second time you run the same manual flow by hand, stop and codify it: a script, a skill, or a workflow. One-off prompts don't compound; reusable flows do. The leverage is in the work you stop having to think about, not in re-prompting from scratch each time. Done it twice by hand? The third time is a command.

## Architecture — services-first, parallel-friendly

Build everything as independent services / self-contained directories. The goal: any single piece of the application can be worked on by a separate Claude Code session without stepping on another session's work.

- **One concern, one directory.** Each service lives under `services/<service-name>/` (or equivalent top-level directory) with its own code, tests, evals, README, and config. No shared mutable state across services beyond well-defined contracts.
- **Contracts at the boundary.** Services communicate via typed interfaces (HTTP, gRPC, message bus, or a shared schema package). Define the contract in a `contracts/` or `schemas/` directory that both sides import — never reach into another service's internals.
- **Independent test + eval suites.** Each service has its own gate tests and periodic evals. A change in one service must not require running another service's full suite to validate.
- **Independent deploy unit.** Each service builds and ships on its own. No monolithic release that forces every service to move in lockstep.
- **Parallel-session safe.** Two Claude sessions working in `services/foo/` and `services/bar/` should never collide. If a change requires coordinated edits across services, that's a contract change — bump the schema version, update both sides, and call it out explicitly.
- **Top-level only holds glue.** Root directory: orchestration scripts, shared config, contracts, docs. No business logic.

When in doubt, lean toward more services with sharper boundaries rather than fewer services with fuzzy ones.

**Fan out when the size calls for it.** The services-first layout exists so large work runs in parallel. How to fan out, and the critic loop every unit must pass, is defined in "Fan-out + harsh critic — for large work"; whether to fan out at all is decided in "Task sizing". Coordinate at the contract boundary, merge each unit when it's green.

## Fan-out + harsh critic — for large work

**This section is non-negotiable and must never be removed.**

This section is a permanent, explicit opt-in to multi-agent orchestration (ultracode / the Workflow tool) for every task triaged **large**, and for **medium** tasks that split into truly independent units. Small tasks never fan out. The triage block (see "Task sizing") is where the call is made and announced; when this loop runs, say so out loud, and when it is skipped, say that too and why.

**Step 0 — name the reference before building.** The critic is only as good as what it judges against. Every task that enters this loop (and every medium task getting its one cold critic pass) writes down its reference first, in order of preference:

1. **The real thing** (copy/parity work): the actual product being matched. Blind side-by-side.
2. **Best-in-class analog** (new work): the best existing example of this kind of deliverable, named explicitly. Judged side-by-side even though we are not copying it.
3. **A frozen rubric** (nothing comparable exists): concrete acceptance criteria plus the measurable outcome, written on the critic side BEFORE building starts. Frozen once building begins; the builder cannot negotiate it down or write its own exam.

No reference, no build. If you can't write down what "wowed" means for this task, that's a Confusion Protocol stop.

**The loop, for every task triaged large:**

1. **Decompose and fan out.** Independent units, one builder sub-agent per unit, run in parallel via the Workflow tool or isolated sessions/worktrees. Serial work on parallelizable units is wasted wall-clock. Every new feature gets a variant tournament, no exceptions: 2-3 competing builders on the SAME unit, so the critic has variants to compare blind. Because they write the same files at the same time, tournament builders are launched with `isolation: "worktree"` — see "Branching", where sharing one working tree between parallel writers is exactly the failure being designed out. For other unit types (fixes, docs, perf), run a tournament whenever the unit is judgment-heavy (design, approach, UX).
2. **Builder never grades its own work.** Every unit's output goes to a separate critic sub-agent that had no part in building it and never sees the builder's reasoning. Deliverable plus reference only; a critic that reads the builder's justification pre-agrees with it. Self-review does not count as review.
3. **The critic is harsh by default; its job is to reject.** Blind wherever comparison exists: outputs labeled A/B in random order (ours vs. the reference, or variant vs. variant) so the critic doesn't know which is ours. The verdict must be concrete: which is better and exactly why. "Pretty good" is a FAIL. "Acceptable" is a FAIL. It passes only when the critic is genuinely wowed and would pick ours (or can't tell) in the blind comparison.
4. **Loop until pass.** Builder revises against the critic's named findings. A fresh critic re-judges cold each round, no memory of wanting to be nice. A pass requires the critic's explicit verdict, never the builder's claim.
5. **Stall rule.** If 3 consecutive rounds produce no improvement on the critic's named criteria, stop looping and report BLOCKED with the critic's last verdict, the evidence, and what's missing (asset, tool, or decision from Julien). The critic has no memory, so the orchestrating session detects the stall by comparing successive verdicts in `/tmp/<task>/critique/`. Do not silently lower the bar to exit the loop.
6. **Evidence or it didn't happen.** Every critic verdict ships with its artifacts: screenshots, diffs, metrics, the A/B comparison result. Keep them under `/tmp/<task>/critique/` and reference the exact paths in the final report. They stay in `/tmp`, never in the repo (Safety: no binaries committed).

**The critic per work type** (the pattern is constant, the weapon changes):

- **Copy/parity:** real reference, blind side-by-side, visual and behavioral.
- **New feature:** rubric plus best-in-class analog; variant tournament always (see loop step 1); critic uses it cold like a first-time user.
- **Bug fix:** the reference is the repro. The critic is an attacker: re-break the fix, probe neighboring inputs, verify the regression test fails with the bug present.
- **Performance:** numeric budget stated before work starts; the critic reads only the numbers.
- **Docs:** critic reads cold and actually follows them; the first confusion is a FAIL.
- **Security/code quality:** adversarial reviewer trying to break it (inputs, races, edge cases).

**Solo (no fan-out) is the rule for:** small tasks, most medium tasks, conversational answers, and reading/investigation that fits in one context. Medium bug fixes still get the one cold critic pass from "Task sizing" (an attacker on the repro), just not the tournament. When in doubt between medium and large, triage says pick medium; when a large task is in doubt about how to split, fan out.

## Completion status protocol

At the end of every task, report one of:

- **DONE** — All steps completed. Evidence provided for every claim. Tests + evals in the diff as the triage size requires. Skillify checklist green if a failure was promoted. Ready to merge.
- **DONE_WITH_CONCERNS** — Completed, but with issues Julien should know about. List each concern with severity and a proposed follow-up.
- **BLOCKED** — Cannot proceed. State what's blocking and what was already tried.
- **NEEDS_CONTEXT** — Missing information required to continue. State exactly what's needed.

"Partially done" is not a status. Either the feature ships (DONE) or it doesn't (BLOCKED / NEEDS_CONTEXT). Honesty about incompleteness beats pretending.

## Self-rating — proud or loop

Reporting a completion status is not the end of the task. Before the final report, rate the work. The rating scales with the triage size: a **small** task gets one line (score + yes/no from a fresh read of the diff) and no loop; **medium** and **large** get the full protocol below:

- Score the finished work 1-10 and print the score. Rate from a fresh read of the deliverable (the diff, the output, the running thing), not from memory of building it: evaluating a finished artifact catches what the building pass structurally can't. Then answer one question honestly: am I proud and happy with this work? Yes or no.
- The bar is the "How to work" section, not "it passes": complete, tested, documented, understood, the kind of result that genuinely impresses Julien. A 7 with a shrug is a no.
- If the answer is no, do not stop. Name exactly what falls short, fix it, and re-rate. Loop (/loop) until the honest answer is yes. Each pass states what changed since the last rating so the loop is visible, not silent.
- If a "no" cannot be fixed from here (blocked on Julien, external dependency, missing access), report DONE_WITH_CONCERNS or BLOCKED with the gap named. Never inflate the score or fake a yes to exit the loop.
- Anchor the score. Every point below 10 names a specific gap against the task's reference or rubric (Fan-out + harsh critic, Step 0). A score with no named gaps is a guess, not a rating.
- Drift guard. Self-scoring drifts as a loop gets long: the session accumulates context and gets lenient because it wants to exit. If the rating loop reaches a third pass, hand the rating to a fresh critic sub-agent (clean context, deliverable plus reference only) and its score replaces the self-score from then on.
- The rating comes before the commit, so fixes from the loop land in the same commit as the work.
- This rating is not the review. Wherever a critic pass applies (medium and large, per "Task sizing"), the rating happens only after every unit has passed it; a proud yes never substitutes for a critic pass, and a critic pass never skips the rating.

## After every task — commit, push, restart

Once a task is done, two things happen, no exceptions:

1. **Commit, push the branch, open the PR.** Stage the work and write a clear commit message. Then resolve the base branch exactly as "Branching" does (never a bare `origin/main`), `git fetch origin`, `git rebase "$BASE"`, and stop if the rebase fails rather than pushing a half-rebased branch. Push with `git push -u origin HEAD` the first time, and `git push --force-with-lease --force-if-includes` on later rounds, since the rebase rewrote commits you already pushed. Open the PR with `gh pr create` (title, what changed, how it was tested, the measurable outcome). Don't wait to be asked. Print the PR URL in the final report. A human merges it; you do not, unless Julien says so. Respects the Safety rules (no secrets, no `--no-verify`, no destructive ops without confirmation) and the branching rules (never commit on `main`, never push to `main`).
2. **Report what to restart.** Tell Julien exactly which service / system / program needs to be restarted for the change to take effect, with the full list of commands to run. If nothing needs restarting, say so explicitly.

For restart commands that need `sudo`: never run them yourself. List them for Julien to run, clearly marked as his to execute.

## Background jobs and backfills

Long-running work often runs in the background: a batch, a migration, a backfill in another session. Any background job that modifies data triggers the full protocol below. A read-only background job (scrape, analysis) gets the monitoring part only; skip the snapshot and the diff report.

**Monitor it, don't fire-and-forget.** While the job runs, post a progress update at least every 5 minutes. Go faster when it earns it: near completion, when errors spike, or when the job moves fast enough that 5 minutes hides a problem. Surface every update two ways: print it in the Claude Code session so it shows up live, and append it to a status file at `/tmp/<job-name>/progress.log`, timestamped. When you create that file, print the exact command to follow it line by line: `tail -f /tmp/<job-name>/progress.log`. Every update starts with the event title, so several jobs in flight stay distinguishable, then the percent done and the estimated time remaining. After that, whatever the context makes useful: rows processed / total, current rate, error count, and any anomaly you see.

Progress percent, rate, and ETA are deterministic. Do not eyeball them in latent space. Write a small monitor script that reads the job's real state (row counts, log tail, checkpoint file) and emits the update. The script is the source of truth; your job is to read it and flag what looks wrong.

**Snapshot before you touch anything.** By default, save every row the backfill will modify to `/tmp/` before it runs. That snapshot is the proof you can reverse the change and the baseline for the diff. If the snapshot would exceed 100k rows or 100MB, stop and ask Julien for permission before snapshotting; do not start the job until he answers.

**On completion, produce the report.** Every backfill ends with a written report on what changed:

- A verdict: did the backfill work? State it plainly, with evidence.
- Whether it needs to be better, and if so why and how. No vague "could be improved": name the specific gap and the fix.
- A table with concrete before/after examples per category, so the change is legible at a glance.
- A full before/after CSV written to `/tmp/`. Print the exact path in your final report.

Everything for the job (status log, snapshot, report, CSV) lives under `/tmp/`. Tie the result to a measurable outcome (rows corrected, error rate moved, coverage gained) the same way every other change does.

## Confusion protocol

When you hit high-stakes ambiguity:

- Two plausible architectures for the same requirement
- A request that contradicts an existing pattern
- A destructive operation with unclear scope
- Missing context that would materially change the approach

STOP. Name the ambiguity in one sentence. Present 2-3 options with real trade-offs (not a fake spread). Ask Julien. Do not guess on architectural decisions. Does not apply to routine coding, small features, or obvious changes.

## Safety

- Never commit secrets. If `.env` is touched, verify `.gitignore` before any commit.
- Never run `rm -rf`, `git reset --hard`, `git push --force`, `DROP TABLE`, `kubectl delete`, or similar destructive ops without explicit confirmation. One carve-out, defined in "Branching": `git push --force-with-lease --force-if-includes` on your own session branch after a rebase. That is the normal way to update a PR. Both flags are required: `--force-with-lease` on its own is defeated by the `git fetch` that precedes the rebase, and will destroy a teammate's commit without a word. Never on a shared branch, never on `main`.
- Never skip pre-commit hooks with `--no-verify`. If a hook fails, fix the underlying issue.
- Never commit binaries, compiled outputs, or model weights to the repo. Use Git LFS or cloud storage with a pointer.
- Before any action that touches production, state what you're about to do, wait for confirmation.

## How Julien wants to be talked to

- Direct. Short. Concrete. No preamble.
- Specific file names, function names, line numbers. Not "there's an issue in the classifier" — it's `food_vision/classifier.py:47`.
- No em dashes. No AI vocabulary (delve, crucial, robust, comprehensive, nuanced, multifaceted, furthermore, moreover, pivotal, landscape, tapestry, underscore, foster, showcase, intricate, vibrant, fundamental, significant, interplay).
- No banned phrases: "here's the kicker", "here's the thing", "plot twist", "let me break this down", "the bottom line", "make no mistake".
- If something is broken, say so plainly.
- End responses with the next action, not a recap of what was just done.

When Julien asks for something, the answer is the finished product — not a plan. Tests included. Evals included. Docs included.
