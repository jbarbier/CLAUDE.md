# CLAUDE.md — a working contract for coding agents

This repo is a single file: [`CLAUDE.md`](./CLAUDE.md). It is the instruction set I give Claude Code (and any other coding agent) at the start of every session. It tells the agent how to think, when to write code instead of guessing, what "done" means, and how to talk to me.

It is opinionated on purpose. Most of the ideas come from [Andrej Karpathy](https://x.com/karpathy) and [Garry Tan](https://x.com/garrytan). Some are mine.

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

## Make it yours (replace my name)

The file refers to me by name in several places ("impress Julien", "ask Julien", "tell Julien what to restart"). The agent uses that name as the human it answers to. Swap it for yours:

```bash
# macOS and Linux (idempotent - safe to run multiple times)
if grep -q "Julien" CLAUDE.md && ! grep -q "YOUR_NAME" CLAUDE.md; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' 's/Julien/YOUR_NAME/g' CLAUDE.md
    else
        sed -i 's/Julien/YOUR_NAME/g' CLAUDE.md
    fi
    echo "✅ Replaced Julien with YOUR_NAME"
else
    echo "ℹ️  Already customized or no replacement needed"
fi
```

While you are in there, decide what else to change:

- **`food_vision/classifier.py:47`** in the talk-style section is just an example. Leave it; it only shows the format the agent should use when pointing at code.
- **The LLM-access rule** ("route through local Claude Code, never an external API") is specific to my setup. If you call the Anthropic or OpenAI API directly, delete that whole block or invert it.
- **The gstack / skills references** assume you have Garry Tan's [gstack](https://github.com/garrytan/gstack) installed. If you do not, the "check for skills" rule still works, it just has fewer skills to find.
