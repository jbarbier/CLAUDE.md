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

If your tool does not follow symlinks, just copy the file and rename it. The rules do not care what the file is called.

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
- **The branching rule** ("one session, one worktree, one branch") assumes you work on a team and review through pull requests. It gives every Claude Code session its own git worktree so two sessions in the same repo stop yanking the branch out from under each other. It picks your branch prefix from your GitHub login; set it explicitly with `git config --global claude.branchPrefix YOUR_HANDLE`. If you work solo and commit straight to `main`, delete the section.
