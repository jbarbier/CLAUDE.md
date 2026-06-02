# CLAUDE.md — a working contract for coding agents

This repo is a single file: [`CLAUDE.md`](./CLAUDE.md). It is the instruction set I give Claude Code (and any other coding agent) at the start of every session. It tells the agent how to think, when to write code instead of guessing, what "done" means, and how to talk to me.

It is opinionated on purpose. Most of the ideas come from Andrej Karpathy and Garry Tan. Some are mine. Every rule below is tagged with where it came from and why it earns its place. Links to the original talks and tweets are at the bottom.

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
# macOS
sed -i '' 's/Julien/YOUR_NAME/g' CLAUDE.md

# Linux
sed -i 's/Julien/YOUR_NAME/g' CLAUDE.md
```

While you are in there, decide what else to change:

- **`food_vision/classifier.py:47`** in the talk-style section is just an example. Leave it; it only shows the format the agent should use when pointing at code.
- **The LLM-access rule** ("route through local Claude Code, never an external API") is specific to my setup. If you call the Anthropic or OpenAI API directly, delete that whole block or invert it. See the rule explanation below before you decide.
- **The gstack / skills references** assume you have Garry Tan's [gstack](https://github.com/garrytan/gstack) installed. If you do not, the "check for skills" rule still works, it just has fewer skills to find.

---

## The rules, explained

Each rule below maps to a section in `CLAUDE.md`. For each one: what it says, where it came from, why it works, and how much it matters. The "matters" rating is my own field experience, not gospel.

### 1. The marginal cost of completeness is near zero — do the whole thing

> "Do it right. Do it with tests. Do it with documentation... The standard isn't 'good enough', it's 'holy shit, that's done.'"

**Where it's from:** Mine, built on Karpathy's [Software 3.0 framing](https://www.latent.space/p/s3) of intelligence as a cheap, abundant resource. When typing is no longer the bottleneck, "I didn't have time to add tests" stops being true.

**Why it works:** The old reason to cut corners was human labor cost. With an agent, the extra 20 minutes to add tests, docs, and edge-case handling is nearly free. So the rule removes "later" as an option. The agent stops asking to "table this for now" and just finishes.

**How much it matters:** High. This single paragraph changes more agent behavior than any other. It is the difference between a draft and a deliverable.

### 2. You cannot outsource the understanding

> "You can outsource the typing. You cannot outsource the understanding... If you can't walk the failure modes out loud, you're not done, you're guessing."

**Where it's from:** Mine, as a direct counterweight to Karpathy's [vibe coding](https://x.com/karpathy/status/1886192184808149383) ("forget that the code even exists"). Vibe coding is great for throwaways and dangerous for anything you ship.

**Why it works:** "Tests pass" is not the same as "this is correct." An agent can write code that passes its own tests and is still wrong about the problem. Forcing it to explain where the code would break surfaces the gap between working and understood.

**How much it matters:** High, and rising as agents get more autonomous. This is the brake on the vibe-coding accelerator.

### 3. The two machine spaces — latent vs deterministic

> "If the same question asked twice would produce the same correct answer by definition, it's deterministic work. Do NOT do it in latent space. Write the script."

**Where it's from:** Karpathy's [Software 1.0 / 2.0 / 3.0](https://karpathy.medium.com/software-2-0-a64152b37c35) progression, plus the [Software 3.0 talk](https://www.latent.space/p/s3) where he frames the LLM as a new kind of computer with the context window as its memory. The "write the script so the script constrains the model forever after" meta-loop is my extension.

**Why it works:** LLMs are bad at arithmetic, date math, and exact lookups, and they are non-deterministic. Code is perfect at those and free to run. The rule stops the agent from doing in an expensive, unverifiable token stream what a five-line script would do correctly every time. A bug in latent space becomes a feature in deterministic space once you codify it.

**How much it matters:** Very high. This is the most load-bearing engineering idea in the file. Most bad agent output is a deterministic task done in latent space.

### 4. The context window is the lever

> "The context window is your only control surface over the model... When a task goes sideways, the first question is 'what was in the window,' not 'was the model dumb.'"

**Where it's from:** Karpathy's [context engineering tweet](https://x.com/karpathy/status/1937902205765607626): "context engineering is the delicate art and science of filling the context window with just the right information for the next step."

**Why it works:** The model only knows what is in its window. Garbage or noise in, garbage out. Treating context as a deliberate, curated input (the spec, the contract, the relevant files, concrete examples, and nothing else) is the highest-leverage thing you control. It reframes debugging from "the model is dumb" to "I fed it the wrong context."

**How much it matters:** Very high. Once you internalize this you stop blaming the model and start curating its input.

### 5. Tests and evals, every time, no exceptions

> "Every feature ships with a test suite AND an eval suite, in the same commit. Not the next PR."

**Where it's from:** Standard engineering discipline, sharpened by Garry Tan's warning that [without review, tests, and judgment, speed turns into cleanup debt](https://github.com/garrytan/gstack). The two-lane split (free deterministic gate tests vs paid LLM evals) maps onto rule 3: tests cover the deterministic half, evals cover the latent half.

**Why it works:** "I'll add tests later" never happens. Putting them in the same commit makes the test the proof the feature works and the eval the proof it generalizes. When the agent can move fast, the only thing keeping it honest is a gate it cannot skip.

**How much it matters:** High. This is the discipline that lets you trust agent output at speed.

### 6. Tie every change to a measurable outcome

> "Every feature names the outcome it moves before you build it... 'It works' is not an outcome."

**Where it's from:** Mine, in the spirit of Tan's "agency and taste" framing: agents generate infinite plausible work, so the scarce input is judgment about what is worth doing.

**Why it works:** Agents will happily build things nobody needs. Naming the metric or user-visible behavior before building filters out theater. "Wire in the trace" means the change leaves evidence (a log line, a metric, an eval score) you can point at later.

**How much it matters:** Medium-high. Saves you from impressive-looking work that moves nothing.

### 7. LLM access — local Claude Code, not the API

> "Do NOT use an LLM API... Route the call through the local Claude Code instead."

**Where it's from:** Mine, and specific to my setup. **Most people should change this rule.**

**Why I do it:** I already pay for Claude Code, so routing in-app LLM calls through the local instance avoids a second metered API bill and keeps one model of record. If you build products that call the Anthropic or OpenAI API directly, delete this block or flip it to name your provider. The useful part to keep is the last line: "always use the best available model by default, no silent downgrades for cost."

**How much it matters:** Low for you (it is my plumbing), except the no-silent-downgrade clause, which is worth keeping.

### 8. Tech choice — vanilla by default, and search before building

> "Simplest vanilla tech wins. No framework-of-the-month... Do not recreate what already exists."

**Where it's from:** Long-standing engineering wisdom; the structured "three layers" search (tried-and-true, then new-and-popular, then first-principles) is my formalization.

**Why it works:** Agents love to write clever custom abstractions and pull in trendy dependencies. Forcing "is there a standard library for this?" first, and requiring written justification before going custom, keeps the codebase boring and maintainable. Boring is good. Boring survives.

**How much it matters:** Medium-high. Prevents the slow accretion of clever code that nobody can maintain.

### 9. Check for skills

> "When a task matches a specialized domain... use the installed Claude Code skill. Don't reinvent."

**Where it's from:** Garry Tan / [gstack](https://github.com/garrytan/gstack), which packages dozens of specialized skills (SEO, design review, QA, security). If you do not run gstack, this rule still applies to whatever skills you do have installed.

**Why it works:** A purpose-built skill beats a freshly improvised approach almost every time. The rule stops the agent from re-implementing a solved problem badly.

**How much it matters:** Medium, scaling with how many skills you have installed.

### 10. Skillify repeated success, not just failure

> "Done it twice by hand? The third time is a command."

**Where it's from:** Garry Tan / gstack's [`/skillify`](https://github.com/garrytan/gstack) idea, extended from failures to successes. Tan's whole leverage comes from codifying flows into reusable tools.

**Why it works:** One-off prompts do not compound. Reusable flows do. The leverage is in the work you stop having to think about. The rule turns the second manual repetition into a trigger to codify.

**How much it matters:** Medium, compounding. Low value on day one, high value by month three.

### 11. Architecture — services-first, parallel-friendly

> "Build everything as independent services... Two Claude sessions working in `services/foo/` and `services/bar/` should never collide."

**Where it's from:** Garry Tan's workflow of [running 10 to 15 agent sprints at once](https://www.aibuilderclub.com/blog/garry-tan-ai-coding-workflow). Sharp service boundaries are what make that parallelism possible without merge wars.

**Why it works:** The bottleneck in agent-driven development is no longer typing, it is coordination. If every concern lives in its own directory with its own tests and contracts, you can fan out N agents on N services with zero collisions. Fuzzy boundaries force serial work and waste the main advantage agents give you.

**How much it matters:** High if you run multiple agents in parallel, medium if you work one session at a time. It is forward-looking either way.

### 12. Fan out by default

> "Serial work on parallelizable units is wasted wall-clock."

**Where it's from:** Garry Tan, directly. This is the operating principle behind his throughput.

**Why it works:** Independent units have no reason to run one after another. The rule makes parallel the default and serial the exception you have to justify.

**How much it matters:** High once you are comfortable running multiple sessions or worktrees, otherwise aspirational.

### 13. Completion status protocol

> "DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT. 'Partially done' is not a status."

**Where it's from:** Mine. A forcing function for honesty.

**Why it works:** Agents are trained to be agreeable, which means they round "mostly working" up to "done." Four explicit statuses with hard definitions make the agent state plainly when something is incomplete or blocked, instead of burying it in optimistic prose.

**How much it matters:** High for trust. You stop having to re-verify every "done" by hand.

### 14. Confusion protocol

> "STOP. Name the ambiguity in one sentence. Present 2-3 options with real trade-offs. Ask."

**Where it's from:** Mine. The counterweight to agent over-confidence on architecture.

**Why it works:** Agents guess on ambiguous, high-stakes decisions rather than asking, and a wrong architectural guess is expensive to unwind. The rule scopes asking tightly (only high-stakes ambiguity, never routine coding) so you get stopped at the decisions that matter and nowhere else.

**How much it matters:** High. One avoided wrong-architecture rabbit hole pays for the whole file.

### 15. Safety

> "Never commit secrets. Never run `rm -rf`, `git reset --hard`, `git push --force`... without explicit confirmation. Never skip pre-commit hooks with `--no-verify`."

**Where it's from:** Mine, plus hard-won universal scar tissue.

**Why it works:** Agents will run destructive commands if a task seems to call for them. An explicit deny-list with a confirmation requirement turns the dangerous defaults off. Keep this section close to verbatim.

**How much it matters:** Very high. This is the one section you should not delete.

### 16. After every task — commit, push, restart

> "Commit and push, don't wait to be asked. Then report exactly what to restart."

**Where it's from:** Mine, operational.

**Why it works:** It closes the loop. Work that is done but uncommitted is not really done, and a change that needs a service restart is not really live until someone restarts it. The rule makes the agent finish the last mile and tell you precisely which commands to run (and which need `sudo`, so you run those, not it).

**How much it matters:** Medium. Pure quality-of-life, but it removes friction from every single task.

### 17. How Julien wants to be talked to

> "Direct. Short. Concrete. No preamble... No em dashes. No AI vocabulary (delve, crucial, robust, comprehensive...)."

**Where it's from:** Mine, a personal style filter. Yours will differ.

**Why it works:** Default agent prose is padded and hedged. A concrete banned-words list and a "specific file names and line numbers" rule force the output into something you can act on. This README follows that style on purpose, so you can see what it produces.

**How much it matters:** Medium. It does not change correctness, it changes how fast you can read the output. Rewrite this section in your own voice.

---

## Which rules are universal, which are mine

If you want a smaller starting point, keep the universal ones and drop the rest until you need them.

**Keep these no matter what:** completeness (1), understanding (2), latent vs deterministic (3), context window (4), tests and evals (5), safety (15), completion status (13), confusion protocol (14).

**Adapt to your stack:** LLM access (7) is mine, change it. Services-first (11) and fan-out (12) matter most when you run parallel agents. Skills (9, 10) assume gstack. Talk-style (17) is my voice, write your own.

---

## Make it better

This file is not finished and is not meant to be. Treat it as a living contract:

- **When the agent does something dumb, write the rule that would have stopped it.** Most of these rules exist because something went wrong once.
- **When you find yourself repeating an instruction in chat, move it into the file.** If you said it twice, it belongs here (rule 10 applies to the file itself).
- **Keep it short.** Every line competes for context window space (rule 4). A bloated `CLAUDE.md` is its own failure mode. Cut rules that no longer earn their tokens.
- **Test a change before trusting it.** Run a real task with the new rule, watch the behavior shift, then keep or revert.

Pull requests and forks welcome. If you write a rule that clearly beats one of mine, open a PR and tell me why.

---

## Sources

The ideas behind these rules, with primary links so you can read them yourself.

**Andrej Karpathy**
- [Software 2.0](https://karpathy.medium.com/software-2-0-a64152b37c35) (Medium, 2017) — neural nets as a new software paradigm; the seed of the latent-vs-deterministic split.
- [Software Is Changing (Again) / Software 3.0](https://www.latent.space/p/s3) (YC AI Startup School talk, June 2025) — LLMs as a new kind of computer, context window as memory, jagged intelligence, the autonomy slider.
- [Context engineering](https://x.com/karpathy/status/1937902205765607626) (X, June 2025) — "the delicate art and science of filling the context window with just the right information for the next step."
- [Vibe coding](https://x.com/karpathy/status/1886192184808149383) (X, February 2025) — the original tweet, and the thing rule 2 deliberately pushes back on.

**Garry Tan**
- [gstack](https://github.com/garrytan/gstack) — his open-sourced Claude Code setup: skills, the sprint loop, skillify, and the services-first parallel workflow.
- [How Garry Tan ships with AI](https://www.aibuilderclub.com/blog/garry-tan-ai-coding-workflow) — the 10-to-15-parallel-sprints workflow behind the fan-out and services-first rules.

**Me:** completeness, understanding accountability, the deterministic meta-loop, completion status, confusion protocol, safety, commit-push-restart, and the talk-style filter.

---

## License

Do whatever you want with it. Copy it, fork it, sell the course you teach with it. Attribution appreciated, not required. The ideas from Karpathy and Tan are theirs; the assembly is mine.
