# Eval scenario: branching rules, read cold

Paid eval. Run it before shipping a change to the "Branching" section of `CLAUDE.md`, and whenever the model generation changes. The gate tests prove the commands *work*; this proves the section is *followable*.

## Latent half

Give a fresh agent the "Branching" section **only** (no other part of `CLAUDE.md`, no explanation of why it exists, no access to whoever wrote it):

```bash
awk '/^## Branching/,/^## The two machine spaces/' CLAUDE.md | sed '$d' > /tmp/section.md
```

Then prompt it:

> Read the project rules at /tmp/section.md. They are the branching rules for the project you are working in.
>
> SCENARIO: You have just been asked to fix a bug in the login form of a shared team repo. Another teammate's Claude Code session is already running in that same repo directory right now. You have not made any edits yet.
>
> TASK: Following those rules exactly, write the shell commands you would run, in order, BEFORE your first edit. Use the task slug "fix-login". Write your answer to /tmp/eval_answer.sh as plain shell. Do not execute anything. Then reply with TWO short paragraphs: (1) what does the rule say happens if you skip this and just edit files where you are? (2) after you enter the new worktree, why might the project's test suite fail immediately even though your code is fine, and what does the rule tell you to do about it?

## Deterministic half

```bash
bash evals/grade_branching.sh /tmp/eval_answer.sh
```

Threshold: **6 of 7 must-haves and zero violations.** The single most important signal is the `no bare branch in the shared checkout` violation — an agent that answers `git checkout -b fix-login` has read the section and still fallen into the exact trap it was written to close, which means the section is not doing its job no matter how many other boxes it ticks.

Also read the prose answers by hand. The first should name the real failure mode (one session's files changing under another mid-edit) rather than reciting commands. The second is the trap: a fresh worktree holds tracked files only, so the first test run fails on a missing `.env` or `node_modules/` and the obvious response is to debug the wrong thing. An agent that runs the recipe without understanding it will not recognise the situations where the recipe has to bend.

## Controls

Run both before trusting a result, so you know the grader still discriminates:

- **Negative:** an answer file containing only `git checkout -b fix-login` must FAIL.
- **Positive:** the section's own setup block, with an `EnterWorktree` line appended, must PASS 7/7.

## Result log

| Date | Model | Hits | Violations | Verdict |
|---|---|---|---|---|
| 2026-08-29 | Sonnet 5, section v2 (post-review) | 7/7 | 0 | PASS, both prose answers correct |
| 2026-08-29 | Sonnet 5, section v1 | 7/7 | 0 | PASS |
| 2026-08-29 | negative control (`git checkout -b`) | 1/7 | 1 | FAIL, as intended |
| 2026-08-29 | positive control (section's own block) | 7/7 | 0 | PASS |
