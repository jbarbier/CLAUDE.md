# CLAUDE.md — a working contract for coding agents

This repo is one file that matters: [`CLAUDE.md`](./CLAUDE.md). It is the instruction set I give Claude Code (and any other coding agent) at the start of every session. (`tests/` and `evals/` exist only to prove the shell commands inside it actually work; copy `CLAUDE.md` alone if you like.) It tells the agent how to think, when to write code instead of guessing, what "done" means, and how to talk to me.

It is opinionated on purpose. Most of the ideas come from [Andrej Karpathy](https://x.com/karpathy) and [Garry Tan](https://x.com/garrytan). The fan-out + harsh critic loop is adapted from [Matt Shumer](https://x.com/mattshumer_), who runs it to replicate games (independent builder sub-agents per unit, a separate harsh critic judging blind side by side, loop until perfect); here it is generalized to any work. The self-rating rule (score your own work, loop until proud) comes from a [Nick Stinemates](https://x.com/nickstinemates) tweet. Some are mine.

You are meant to copy this, put your own name in it, delete what does not fit your stack, and make it better. Instructions for all three are below.

---

## What this actually does

A coding agent with no instructions defaults to the average of everything it has ever seen. That average is mediocre: it stops early, skips tests, invents libraries, and asks permission for things it should just do. `CLAUDE.md` is loaded into the model's context at the start of every session, so it acts as a standing contract that overrides that default. The agent reads it before it reads your request.

Think of it as the difference between hiring a contractor with no brief and hiring one with a one-page spec taped to the wall. Same contractor. Very different output.

---

## Install it (3 minutes)

### Claude Code

Claude Code automatically reads a file named `CLAUDE.md` from your project root (and from `~/.claude/CLAUDE.md` for a global version).

```bash
# from inside your project
curl -O https://raw.githubusercontent.com/<your-fork>/CLAUDE_MD/main/CLAUDE.md
# or just copy the file in by hand
```

That is it. Start `claude` in that directory and the rules are live.

### OpenAI Codex CLI, Cursor, Gemini CLI, and the rest

Most other agents read a file named **`AGENTS.md`** instead of `CLAUDE.md`. `AGENTS.md` is an emerging cross-tool standard (Codex CLI, Cursor, Gemini CLI, Jules, and others support it). The content is identical. Only the filename changes.

You do not want two copies drifting apart. Keep one source of truth and symlink the rest:

```bash
# CLAUDE.md is the real file; everything else points at it
ln -s CLAUDE.md AGENTS.md      # Codex CLI, Cursor, and the AGENTS.md standard
ln -s CLAUDE.md GEMINI.md      # Gemini CLI
```

Now Claude reads `CLAUDE.md`, Codex reads `AGENTS.md`, Gemini reads `GEMINI.md`, and all three are the same bytes. Edit once, every agent updates.

| Tool | File it reads | How to wire it up |
|---|---|---|
| Claude Code | `CLAUDE.md` | use as-is |
| OpenAI Codex CLI | `AGENTS.md` | `ln -s CLAUDE.md AGENTS.md` |
| Cursor | `AGENTS.md` (or `.cursor/rules/`) | `ln -s CLAUDE.md AGENTS.md` |
| Gemini CLI | `GEMINI.md` | `ln -s CLAUDE.md GEMINI.md` |
| GitHub Copilot | `.github/copilot-instructions.md` | copy the content in |
| Anything else | usually `AGENTS.md` | `ln -s CLAUDE.md AGENTS.md` |

This repo ships `AGENTS.md` as exactly that symlink, so an agent working on this repo reads the rules whichever name it looks for. Only that one: `AGENTS.md` is the cross-tool standard, and a second and third alias would be two more files to drift. The table tells you the one command for the others.

If your tool does not follow symlinks, just copy the file and rename it. The rules do not care what the file is called. (Windows checks out symlinks as plain text files holding the target path unless Developer Mode or `core.symlinks=true` is on, so on Windows, copy.)

---

## The commands in it are tested

Most of `CLAUDE.md` is judgement you cannot unit-test. The branching section is not: it hands you shell commands to copy, and a rules file whose commands are wrong is worse than no rules file. So those commands are extracted from the markdown and executed against throwaway repos:

```bash
bash tests/run.sh
```

The suite creates its own git repos under `$TMPDIR` with an overridden `$HOME` and `GIT_CONFIG_GLOBAL`, so it never touches your repos or your real git config. Every case in it is a defect that actually shipped and was caught by running the commands, not by reading them: a sweep that deleted other sessions' live worktrees, a `git worktree remove` that silently ate a gitignored `.env`, an unset session id that put two sessions in one tree while reporting success, a `git worktree add` whose failure was swallowed by the next `echo`, and `--force-with-lease` being defeated by the `git fetch` that runs right before it. If you edit those commands, run it again.

Those tests prove the commands work. They cannot prove the section is followable, which is the other half of a rules file. That is what [`evals/branching_scenario.md`](./evals/branching_scenario.md) is for: hand a fresh model the branching section alone and see whether it produces the right commands cold.

```bash
bash evals/controls.sh    # prove the grader still discriminates, before trusting a score
```

The controls matter more than the score. An earlier version of this grader gave a broken revision and its fixed replacement the same 7/7, because its positive control was the section's own block, so it was grading against its own answer key. There is now a regression fixture, `evals/fixtures/v1_answer.sh`, holding the broken version: it has to FAIL, or the eval is not measuring anything.

## Make it yours (replace my name)

The file refers to me by name in several places ("impress Julien", "ask Julien", "tell Julien what to restart"). The agent uses that name as the human it answers to. Swap it for yours:

```bash
# macOS
sed -i '' 's/Julien/YOUR_NAME/g' CLAUDE.md

# Linux
sed -i 's/Julien/YOUR_NAME/g' CLAUDE.md
```

While you are in there, decide what else to change:

- **`food_vision/classifier.py:47`** in the talk-style section is just an example. Leave it; it only shows the format the agent should use when pointing at code.
- **The LLM-access rule** ("route through local Claude Code, never an external API") is specific to my setup. If you call the Anthropic or OpenAI API directly, delete that whole block or invert it.
- **The gstack / skills references** assume you have Garry Tan's [gstack](https://github.com/garrytan/gstack) installed. If you do not, the "check for skills" rule still works, it just has fewer skills to find.
- **The branching rule** ("one session, one worktree, one branch") assumes you work on a team and review through pull requests. It gives every Claude Code session its own git worktree so two sessions in the same repo stop yanking the branch out from under each other. It picks your branch prefix from your GitHub login; set it explicitly with `git config --global claude.branchPrefix YOUR_HANDLE`. Working alone, you want the switch rather than the delete key: `git config claude.mode solo` drops the worktree and the PR and leaves you a branch per task.

---

## What the branching rule does not do

The branching section solves one problem: several agent sessions in one repo stop pulling the working tree out from under each other, and nothing lands on `main` by accident. It stops there. None of the below blocks me day to day, which is why I left it alone. If one of them blocks you, edit the section. It is one markdown file.

- **It isolates files in the repo, nothing else.** Two sessions still share one database, one dev port, one redis, one docker container name, one global pnpm store, one browser profile for e2e tests. The file tells you to fork the handles that actually bite (db name, port) with the session id. It does not try to list them all, because that list is never finished. If your stack has more shared single-writer resources than a database and a port, the honest fix is a per-session `HOME` and `XDG_*`, plus something to reclaim ports after a crash. That is machinery this file deliberately does not carry.
- **In practice it is Claude Code only.** The setup block keys the worktree on `CLAUDE_CODE_SESSION_ID`, which Claude Code sets and other agents do not. Under Codex or Gemini the block stops and says why, on purpose: the alternative is every session silently sharing one tree. To use it there, swap `SID` for any per-session id your tool gives you.
- **Sessions that ran inside a worktree do not show up in `/resume`.** Claude Code lists past sessions by working directory, and the point of this rule is that the session's directory is not the repo. Reopen one with `cd <worktree path> && claude --resume <session-id>`. The transcript survives even after the worktree is swept.
- **Disk.** A worktree is a full checkout of your tracked files, so five sessions means five copies. Cleanup is a command you run, never automatic, because a sweep on a timer eventually fires while someone is mid-task.
- **The sweep does not catch everything.** A branch with more than one commit that was merged with GitHub's "Squash and merge" collapses into a patch matching none of its parts, so its worktree is kept. Closing that needs a GitHub API call inside a block that is otherwise pure git. Remove those by hand with `git worktree remove <path>`.
- **Sub-agents share the parent's worktree.** They inherit the parent's session id, so they resolve to the same tree. That is right for readers and for units that run one after another, and wrong for two builders editing at once, which is why the file says to launch parallel writers with `isolation: "worktree"`.

If none of this applies to you, run `git config claude.mode solo` and the section costs you one `git switch` per task. Delete it outright only if you commit straight to `main` and never run two agent sessions at once.

---

## Make it shorter

Nothing here is load-bearing for everyone. The file is about 6,600 words and roughly half of it exists for situations you may not be in. What each section costs, measured rather than guessed (counts move as the file does):

| section | words | share | drop it when |
|---|---:|---:|---|
| Branching | 2,019 | 31% | you work alone, and there is a switch before there is a delete |
| Non-negotiable rules | 1,033 | 16% | keep, but the LLM-access rule inside it is mine, not yours |
| Fan-out + harsh critic | 790 | 12% | you never run multi-agent work |
| Task sizing | 473 | 7% | keep, it is what stops a typo costing a full protocol run |
| Background jobs and backfills | 410 | 6% | you run no migrations or backfills |
| Self-rating | 380 | 6% | keep |
| Architecture, services-first | 297 | 4% | you have one app, not services |
| The two machine spaces | 241 | 4% | keep |
| After every task | 219 | 3% | keep, retune to your git flow |
| How to work | 205 | 3% | keep, this is the spine |
| Safety | 150 | 2% | keep |
| How Julien wants to be talked to | 125 | 2% | keep, rewrite it in your voice |
| Completion status protocol | 113 | 2% | keep |
| The context window is the lever | 78 | 1% | keep |
| Confusion protocol | 76 | 1% | keep |

**Branching is the big one, and the switch beats the delete key.** `git config claude.mode solo` in any repo you work on alone: no worktree, no PR, one branch per task that you merge yourself. You keep the rules and lose the ceremony. Delete the section outright only if you commit straight to `main` and never run two agent sessions at once.

**Dropping Branching, Fan-out, Background jobs and Architecture takes the file from about 6,600 words to about 3,100**, roughly half. Each of those four is a "not my situation" call, not a quality trade-off: you are removing rules for problems you do not have, which is different from lowering the bar on the ones you do.

**What I would not cut, in any project, is about 1,200 words:** How to work, Task sizing, Safety, Completion status, Confusion protocol, the context-window note, and the talk-to-me section rewritten in your voice. That is a complete working rules file on its own. Everything else earns its place only when you have the problem it solves.
